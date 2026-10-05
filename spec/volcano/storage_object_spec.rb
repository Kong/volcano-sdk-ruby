# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::StorageObject do
  let(:attributes) do
    { id: 'object', bucket_id: 'bucket', name: 'photo.png', size: 12, mime_type: 'image/png', is_public: false }
  end

  %i[id bucket_id name size mime_type is_public].each do |name|
    it "rejects an object missing #{name}" do
      expect { described_class.new(**attributes.except(name)) }
        .to raise_error(ArgumentError, "missing keywords: #{name}")
    end
  end

  it 'rejects unknown attributes rather than silently dropping them' do
    expect { described_class.new(**attributes, unexpected: 'value') }
      .to raise_error(ArgumentError, 'unknown keywords: unexpected')
  end

  it 'preserves explicit nil separately from an omitted required attribute' do
    object = described_class.new(**attributes, size: nil)

    expect(object.size).to be_nil
    expect(object.name).to eq('photo.png')
    expect(object).to be_frozen
  end
end
