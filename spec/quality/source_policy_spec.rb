# frozen_string_literal: true

require_relative '../../maintainers/quality/source_policy'
require 'tmpdir'
require 'fileutils'

RSpec.describe Quality::SourcePolicy do
  let(:directory) { Dir.mktmpdir('source-policy-spec-') }
  let(:policy) { described_class.new(directory) }

  before do
    system('git', 'init', '--quiet', directory, exception: true)
    write('.rubocop.yml', "AllCops:\n  NewCops: enable\n  TargetRubyVersion: 3.2\n")
    write('lib/example.rb', "VALUE = 1\n")
  end

  after { FileUtils.remove_entry(directory) }

  def write(path, contents)
    target = File.join(directory, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, contents)
  end

  it 'includes new untracked Ruby files in the linter inventory' do
    expect(policy.check).to be_empty
  end

  ['# rubocop:disable all', '# rubocop:todo Metrics/MethodLength', '# :nocov:'].each do |comment|
    it "rejects #{comment} in a maintained Ruby file" do
      write('lib/example.rb', "#{comment}\nVALUE = 1\n")

      expect(policy.check).to include(a_string_including('lib/example.rb:1: inline lint and coverage suppressions'))
    end
  end

  it 'does not mistake fixture strings for suppression comments' do
    write('lib/example.rb', "VALUE = '# rubocop:disable all # :nocov:'\n")

    expect(policy.check).to be_empty
  end

  ['.rubocop_todo.yml', 'lib/.rubocop.yml', 'spec/.rspec', '.simplecov'].each do |path|
    it "rejects override configuration #{path}" do
      write(path, "{}\n")

      expect(policy.check).to include(a_string_including("#{path}: nested overrides and debt-baseline"))
    end
  end

  it 'rejects a new source file excluded by linter configuration' do
    write('.rubocop.yml', "AllCops:\n  NewCops: enable\n  Exclude:\n    - lib/example.rb\n")

    expect(policy.check).to include('lib/example.rb: maintained Ruby source is excluded from RuboCop')
  end

  %w[config.ru view.builder view.jbuilder Guardfile Steepfile].each do |path|
    it "rejects suppressions in conventional Ruby source #{path}" do
      write(path, "# :nocov:\nVALUE = 1\n")

      expect(policy.check).to include(a_string_including("#{path}:1: inline lint and coverage suppressions"))
    end

    it "rejects excluding conventional Ruby source #{path}" do
      write(path, "VALUE = 1\n")
      write('.rubocop.yml', "AllCops:\n  NewCops: enable\n  Exclude:\n    - #{path}\n")

      expect(policy.check).to include("#{path}: maintained Ruby source is excluded from RuboCop")
    end
  end

  it 'rejects inherited debt baselines with arbitrary filenames' do
    write('debt.yml', "Metrics/MethodLength:\n  Exclude:\n    - lib/example.rb\n")
    write('.rubocop.yml', "inherit_from: debt.yml\nAllCops:\n  NewCops: enable\n")

    expect(policy.check).to include(a_string_including('.rubocop.yml: inherited configurations are forbidden'))
  end

  it 'rejects inherited gem configuration' do
    write('.rubocop.yml', "inherit_gem: {}\nAllCops:\n  NewCops: enable\n")

    expect(policy.check).to include(a_string_including('.rubocop.yml: inherited configurations are forbidden'))
  end

  it 'checks Ruby scripts without a filename extension' do
    write('bin/task', "#!/usr/bin/env ruby\n# :nocov:\nputs 'hello'\n")

    expect(policy.check).to include(a_string_including('bin/task:2: inline lint and coverage suppressions'))
  end

  it 'rejects empty source discovery' do
    FileUtils.rm(File.join(directory, 'lib/example.rb'))

    expect(policy.check).to include('No maintained Ruby sources discovered')
  end

  it 'rejects symlinked Ruby sources' do
    File.symlink('example.rb', File.join(directory, 'lib/alias.rb'))

    expect(policy.check).to include('lib/alias.rb: maintained Ruby sources must not be symlinks')
  end

  it 'fails closed when repository discovery cannot run' do
    FileUtils.remove_entry(File.join(directory, '.git'))

    expect { policy.check }.to raise_error(RuntimeError, /Policy discovery failed/)
  end

  it 'makes the executable fail for a suppression' do
    write('lib/example.rb', "# :nocov:\nVALUE = 1\n")
    write('bin/check-source-policy', File.read(File.expand_path('../../bin/check-source-policy', __dir__)))
    implementation = File.expand_path('../../maintainers/quality/source_policy.rb', __dir__)
    write('maintainers/quality/source_policy.rb', File.read(implementation))
    _, errors, status = Open3.capture3(Gem.ruby, 'bin/check-source-policy', chdir: directory)

    expect(status).not_to be_success
    expect(errors).to include('lib/example.rb:1: inline lint and coverage suppressions')
  end
end
