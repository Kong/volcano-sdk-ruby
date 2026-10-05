# frozen_string_literal: true

RSpec.describe Volcano::Transport do
  it 'preserves finite nested JSON responses and caller-owned values' do
    generator = PropCheck::Generators.tuple(
      PropCheck::Generators.printable_string,
      PropCheck::Generators.choose(-10_000..10_000),
      PropCheck::Generators.choose(0..1)
    )
    check_property(generator) do |text, count, flag|
      value = { 'items' => [text, count, flag == 1, nil], 'nested' => { 'text' => text } }
      copy = described_class.json_value(value)

      expect(copy).to eq(value)
      expect(copy).not_to equal(value)
      expect(copy.fetch('items')).not_to equal(value.fetch('items'))
      expect(copy.fetch('nested')).not_to equal(value.fetch('nested'))
    end
  end
end
