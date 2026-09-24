# frozen_string_literal: true

require 'open3'
require 'pathname'
require 'tmpdir'

class SpecFileInventory
  def initialize(root, pattern:, exclude_pattern:)
    @root = root
    @pattern = pattern
    @exclude_pattern = exclude_pattern
  end

  def missing = maintained - discovered

  private

  def maintained
    output, error, status = Open3.capture3(
      'git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z', '--', 'spec', chdir: @root
    )
    raise error unless status.success?

    output.split("\0").grep(/\.rb\z/).reject do |path|
      path == 'spec/spec_helper.rb' || path.start_with?('spec/support/')
    end
  end

  def discovered
    config = RSpec::Core::Configuration.new
    config.pattern = @pattern
    config.exclude_pattern = @exclude_pattern
    config.files_or_directories_to_run = [File.join(@root, 'spec')]
    config.files_to_run.map { |path| Pathname(path).relative_path_from(Pathname(@root)).to_s }
  end
end

RSpec.describe SpecFileInventory do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:inventory) do
    described_class.new(
      root, pattern: RSpec.configuration.pattern, exclude_pattern: RSpec.configuration.exclude_pattern
    )
  end

  it 'includes every maintained spec in native RSpec discovery' do
    expect(inventory.missing).to be_empty
  end

  it 'rejects an added Ruby test with an undiscoverable name' do
    Dir.mktmpdir('volcano-spec-inventory-') do |directory|
      FileUtils.mkdir_p(File.join(directory, 'spec'))
      File.write(File.join(directory, 'spec/forgotten.rb'), "RSpec.describe(String) { it('works') {} }")
      system('git', 'init', '--quiet', directory, exception: true)
      system('git', '-C', directory, 'add', 'spec/forgotten.rb', exception: true)

      probe = described_class.new(directory, pattern: RSpec.configuration.pattern, exclude_pattern: '')
      expect(probe.missing).to eq(['spec/forgotten.rb'])
    end
  end

  it 'rejects a test excluded by a nested RSpec pattern' do
    Dir.mktmpdir('volcano-spec-inventory-') do |directory|
      FileUtils.mkdir_p(File.join(directory, 'spec/nested'))
      File.write(File.join(directory, 'spec/nested/hidden_spec.rb'), "RSpec.describe(String) { it('works') {} }")
      system('git', 'init', '--quiet', directory, exception: true)
      system('git', '-C', directory, 'add', 'spec/nested/hidden_spec.rb', exception: true)

      probe = described_class.new(directory, pattern: 'spec/*_spec.rb', exclude_pattern: '')
      expect(probe.missing).to eq(['spec/nested/hidden_spec.rb'])
    end
  end
end
