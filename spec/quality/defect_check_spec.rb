# frozen_string_literal: true

require_relative '../../maintainers/quality/defect_check'

RSpec.describe Quality::DefectCheck do
  let(:directory) { Dir.mktmpdir('defect-check-spec-') }
  let(:root) { File.join(directory, 'checkout') }
  let(:reports) { File.join(directory, 'reports') }
  let(:defect) do
    { 'name' => 'fixture', 'path' => 'lib/target.rb', 'before' => 'def self.value = 1',
      'after' => 'def self.value = 2', 'spec' => 'spec/target_spec.rb', 'example' => 'returns one' }
  end

  before do
    FileUtils.mkdir_p([root, reports])
    populate_root
    system('git', 'init', '--quiet', root, exception: true)
  end

  after { FileUtils.remove_entry(directory) }

  def populate_root
    project = File.expand_path('../..', __dir__)
    %w[Gemfile Gemfile.lock volcano-sdk.gemspec lib/volcano/version.rb].each do |name|
      write_file(name, File.read(File.join(project, name)))
    end
    write_file('lib/target.rb', "module DefectFixture\n  def self.value = 1\nend\n")
    write_file('spec/target_spec.rb', <<~RUBY)
      require_relative '../lib/target'
      RSpec.describe DefectFixture do
        it('returns one') { expect(described_class.value).to eq(1) }
      end
    RUBY
  end

  def write_file(name, content)
    path = File.join(root, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def check(changes = {})
    described_class.new(root: root, defect: defect.merge(changes), reports: reports).run.fetch(:outcome)
  end

  it 'detects the injected assertion failure and leaves the original source intact' do
    expect(check).to eq('detected')
    expect(File.read(File.join(root, 'lib/target.rb'))).to include('def self.value = 1')
  end

  it 'fails when a valid mutation survives' do
    expect(check('after' => 'def self.value = 1 + 0')).to eq('survived')
  end

  it 'rejects stale patches' do
    expect(check('before' => 'missing source')).to eq('stale_patch')
  end

  it 'rejects ambiguous patches' do
    expect(check('before' => 'e')).to eq('stale_patch')
  end

  it 'rejects overlapping patch matches' do
    write_file('lib/target.rb', "# aaa\nmodule DefectFixture; def self.value = 1; end\n")
    expect(check('before' => 'aa', 'after' => 'b')).to eq('stale_patch')
  end

  it 'rejects an unchanged mutation' do
    expect(check('after' => defect.fetch('before'))).to eq('stale_patch')
  end

  it 'rejects invalid Ruby instead of counting a syntax failure' do
    expect(check('after' => 'def self.value = (')).to eq('invalid_mutation')
  end

  it 'rejects an already failing baseline' do
    write_file('lib/target.rb', "module DefectFixture; def self.value = 0; end\n")
    expect(check).to eq('baseline_failed')
  end

  it 'fails on empty test selection' do
    expect(check('example' => 'missing example')).to eq('baseline_failed')
  end

  it 'does not reuse a previous report after a child exits without writing one' do
    expect(check).to eq('detected')
    expect(check('after' => 'def self.value = exit!(1)')).to eq('harness_error')
    expect(File.read(File.join(reports, 'fixture-mutant.json'))).to be_empty
  end

  it 'does not count a runtime crash as an assertion failure' do
    expect(check('after' => 'def self.value = missing_method')).to eq('harness_error')
  end
end
