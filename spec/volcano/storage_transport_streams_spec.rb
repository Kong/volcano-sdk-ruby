# frozen_string_literal: true

require 'support/read_only_download'

module Volcano
  RSpec.describe StorageBucket do
    let(:storage) { instance_double(GeneratedTransport::StorageApi) }
    let(:apis) { instance_double(GeneratedTransport::GeneratedApis, storage: storage) }
    let(:transport) { GeneratedTransport.new(api_url: 'https://api.test', api_factory: ->(_token) { apis }) }
    let(:client) { Client.new(anon_key: 'anon', access_token: 'access', _transport: transport) }
    let(:bucket) { client.storage.from('assets') }

    it 'preserves bytes from a stream without seeking or tempfile methods' do
      content = "hello\x00\xff".b.force_encoding(Encoding::UTF_8)
      source = SpecSupport::ReadOnlyDownload.new(content)
      allow(storage).to receive(:download_storage_object_with_http_info).and_return([source, 200, nil])

      result = bucket.download('file.bin')

      expect(result).to eq(content.b)
      expect(result.encoding).to eq(Encoding::BINARY)
      expect(content.encoding).to eq(Encoding::UTF_8)
      expect(storage).to have_received(:download_storage_object_with_http_info).with('assets', 'file.bin', {})
    end

    [nil, 42, ['bytes']].each do |value|
      it "rejects a stream returning #{value.inspect} before uploading" do
        source = SpecSupport::ReadOnlyDownload.new(value)
        allow(storage).to receive(:upload_storage_object_with_http_info)

        expect { bucket.upload('file.bin', source) }
          .to raise_error(ArgumentError, 'upload data must be a String or IO')
        expect(storage).not_to have_received(:upload_storage_object_with_http_info)
      end
    end

    it 'omits an empty prefix while preserving pagination in the generated request' do
      allow(storage).to receive(:list_storage_objects_with_http_info)
        .and_return([{ 'objects' => [], 'next_cursor' => 'next' }, 200, {}])

      page = bucket.list('', limit: 2, cursor: 'previous')

      expect(page).to have_attributes(objects: [], next_cursor: 'next')
      expect(storage).to have_received(:list_storage_objects_with_http_info)
        .with('assets', { limit: 2, cursor: 'previous' })
    end
  end
end
