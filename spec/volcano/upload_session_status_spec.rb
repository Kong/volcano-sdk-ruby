# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::UploadSessionStatus do
  let(:attributes) do
    {
      session_id: 'upload', status: 'uploading', path: 'photo.png', content_type: 'image/png',
      total_size: 12, part_size: 6, total_parts: 2, parts_uploaded: 0, bytes_uploaded: 0,
      parts: [], expires_at: '2026-09-22T00:00:00Z', created_at: '2026-09-21T00:00:00Z'
    }
  end

  %i[
    session_id status path content_type total_size part_size total_parts parts_uploaded
    bytes_uploaded parts expires_at created_at
  ].each do |name|
    it "rejects a status missing #{name}" do
      expect { described_class.new(**attributes.except(name)) }
        .to raise_error(ArgumentError, "missing keywords: #{name}")
    end
  end

  it 'rejects unknown attributes rather than silently dropping them' do
    expect { described_class.new(**attributes, unexpected: 'value') }
      .to raise_error(ArgumentError, 'unknown keywords: unexpected')
  end
end
