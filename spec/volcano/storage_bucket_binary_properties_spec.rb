# frozen_string_literal: true

require 'stringio'

RSpec.describe Volcano::StorageBucket do
  let(:bytes) do
    PropCheck::Generators.array(PropCheck::Generators.choose(0..255), max: 256).map { |values| values.pack('C*') }
  end

  def binary_bucket(transport)
    Volcano::Client.new(anon_key: 'anon', access_token: 'access', _transport: transport).storage.from('assets')
  end

  it 'uploads all remaining IO bytes without closing or reinterpreting the source' do
    check_property(bytes) do |payload|
      transport = instance_double(Volcano.const_get(:GeneratedTransport))
      source = StringIO.new("prefix#{payload}".b)
      source.pos = 6
      allow(transport).to receive(:upload_storage_object).with(
        authorization: 'access', bucket_name: 'assets', path: 'file.bin',
        data: payload, content_type: nil
      ).and_return(Volcano::Transport::Response.new(status: 201, body: {}, headers: {}, data: nil))
      binary_bucket(transport).upload('file.bin', source)
      expect(transport).to have_received(:upload_storage_object)
      expect(source).not_to be_closed
      expect(source.pos).to eq(6 + payload.bytesize)
    end
  end

  it 'downloads every byte as binary even when the transport encoding is UTF-8' do
    check_property(bytes) do |payload|
      transport = instance_double(Volcano.const_get(:GeneratedTransport))
      response = Volcano::Transport::Response.new(
        status: 200, body: nil, headers: {}, data: payload.dup.force_encoding(Encoding::UTF_8)
      )
      allow(transport).to receive(:download_storage_object).and_return(response)
      downloaded = binary_bucket(transport).download('file.bin')
      expect(downloaded.bytes).to eq(payload.bytes)
      expect(downloaded.encoding).to eq(Encoding::BINARY)
    end
  end
end
