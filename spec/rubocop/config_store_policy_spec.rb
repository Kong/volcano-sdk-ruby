# frozen_string_literal: true

require 'rubocop'

RSpec.describe RuboCop::ConfigStore do
  let(:root) { File.expand_path('../..', __dir__) }

  it 'keeps native complexity and length limits for every handwritten runtime file' do
    files = Dir.glob(File.join(root, 'lib/**/*.rb')).reject { |path| path.include?('/lib/volcano/generated/') }
    expect(files).not_to be_empty

    store = described_class.new
    files.each do |path|
      config = store.for_file(path)
      expect(config.for_cop('Metrics/CyclomaticComplexity').slice('Enabled', 'Max')).to eq(
        'Enabled' => true, 'Max' => 5
      ), path
      expect(config.for_cop('Metrics/MethodLength').slice('Enabled', 'Max')).to eq(
        'Enabled' => true, 'Max' => 10
      ), path
      expect(config.for_cop('Metrics/ParameterLists').slice('Enabled', 'Max', 'CountKeywordArgs')).to eq(
        'Enabled' => true, 'Max' => 5, 'CountKeywordArgs' => true
      ), path
    end
  end

  it 'keeps every native correctness cop and project-wide analysis enabled' do
    config = described_class.new.for_file(File.join(root, 'lib/volcano/client.rb'))
    disabled = RuboCop::Cop::Registry.global.names.grep(%r{\ALint/}).reject do |name|
      config.for_cop(name)['Enabled']
    end

    expect(disabled).to be_empty
    expect(config.for_all_cops['UseProjectIndex']).to be(true)
  end
end
