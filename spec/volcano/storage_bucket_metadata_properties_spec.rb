# frozen_string_literal: true

RSpec.describe Volcano::StorageBucket do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:bucket) do
    Volcano::Client.new(anon_key: 'anon', access_token: 'access', _transport: transport).storage.from('assets')
  end

  it 'preserves arbitrary finite JSON metadata through a storage object response' do
    generator = PropCheck::Generators.tuple(
      PropCheck::Generators.printable_string,
      PropCheck::Generators.choose(-10_000..10_000),
      PropCheck::Generators.choose(0..1)
    )
    check_property(generator) do |key, number, flag|
      metadata = { key => { 'items' => [number, flag == 1, nil, 'text'] } }
      body = { 'id' => 'object', 'bucket_id' => 'assets', 'name' => 'file.bin', 'size' => 1,
               'mime_type' => 'application/octet-stream', 'is_public' => false, 'metadata' => metadata }
      response = Volcano::Transport::Response.new(status: 200, body: body, headers: {}, data: nil)
      allow(transport).to receive(:move_storage_object).and_return(response)

      object = bucket.move('file.bin', 'moved.bin')

      expect(object.metadata).to eq(metadata)
      expect(object.metadata).to be_frozen
    end
  end
end
