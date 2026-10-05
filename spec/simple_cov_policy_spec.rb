# frozen_string_literal: true

require 'simplecov'

RSpec.describe SimpleCov do
  it 'tracks every runtime file at 100% line and branch coverage' do
    expect(described_class.coverage_criteria).to eq(Set[:line, :branch])
    expect(described_class.minimum_coverage).to eq(line: 100, branch: 100)
    expect(described_class.maximum_missed).to eq(line: 0, branch: 0)
    expect(described_class.cover_globs).to eq(['lib/**/*.rb'])
    expect(described_class.cover_filters.map(&:filter_argument)).to eq(['lib/**/*.rb'])
  end

  it 'excludes only generated runtime code' do
    filters = described_class.filters.map(&:filter_argument)
    expect(filters.grep(String)).to eq(
      ['/vendor/bundle/', '/lib/volcano/generated/']
    )
    expect(filters.grep(Regexp)).to eq(
      [/\A\..*/, %r{\A(test|features|spec|autotest)/}]
    )
    expect(filters.count { |filter| filter.is_a?(Proc) }).to eq(1)
  end
end
