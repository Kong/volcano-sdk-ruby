# frozen_string_literal: true

require_relative '../support/dynamic_annotations'

RSpec.describe SpecSupport::DynamicAnnotations do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:inventory) { described_class.expected_entries(root) }

  it 'matches every native-parsed dynamic annotation to an exact necessary scope' do
    expect(described_class.source_entries(root)).to match_array(inventory)
  end

  it 'keeps the central inventory exact, nonempty, and without duplicate scopes or names' do
    records = described_class.records(root)
    expect(records).not_to be_empty
    expect(records.map(&:keys)).to all(match_array(%w[path scope methods]))
    scopes = records.map { |record| record.values_at('path', 'scope') }
    expect(scopes.uniq.length).to eq(records.length)
    expect(inventory.uniq.length).to eq(inventory.length)
    expect(records.map { |record| record.fetch('methods') }).to all(be_a(Array).and(be_any))
  end

  it 'requires every exception to suppress its exact native missing-method diagnostic' do
    expect(described_class.missing_implementations(root)).to match_array(described_class.expected_diagnostics(root))
  end
end
