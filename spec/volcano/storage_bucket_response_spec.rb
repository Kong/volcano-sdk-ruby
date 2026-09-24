# frozen_string_literal: true

RSpec.describe Volcano::StorageBucket do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:bucket) do
    Volcano::Client.new(anon_key: 'anon', access_token: 'access', _transport: transport).storage.from('assets')
  end

  def response(status, body)
    Volcano::Transport::Response.new(status: status, body: body, headers: {}, data: nil)
  end

  def session_payload
    { 'session_id' => 'upload', 'part_size' => 4, 'total_parts' => 2,
      'expires_at' => '2026-10-01T00:00:00Z' }
  end

  def status_payload
    { 'session_id' => 'upload', 'status' => 'uploading', 'path' => 'file.bin',
      'content_type' => 'application/octet-stream', 'total_size' => 8, 'part_size' => 4,
      'total_parts' => 2, 'parts_uploaded' => 0, 'bytes_uploaded' => 0,
      'expires_at' => '2026-10-01T00:00:00Z', 'created_at' => '2026-09-01T00:00:00Z' }
  end

  def object_payload
    { 'id' => 'object', 'bucket_id' => 'assets', 'name' => 'file.bin', 'size' => 8,
      'mime_type' => 'application/octet-stream', 'is_public' => false }
  end

  it 'returns the original decoded upload hash with timestamps intact' do
    payload = object_payload.merge('created_at' => Time.utc(2026, 9, 23))
    allow(transport).to receive(:upload_storage_object).and_return(response(201, payload))

    expect(bucket.upload('file.bin', 'bytes')).to equal(payload)
  end

  it 'rejects a successful upload body with non-string keys' do
    allow(transport).to receive(:upload_storage_object).and_return(response(201, name: 'file.bin'))

    expect { bucket.upload('file.bin', 'bytes') }
      .to raise_error(Volcano::Error::TransportError, 'invalid storage response key')
  end

  [nil, 42, Object.new].each do |value|
    it "preserves the argument error for unsupported upload input #{value.inspect}" do
      allow(transport).to receive(:upload_storage_object)
      allow(transport).to receive(:upload_part)

      expect { bucket.upload('file.bin', value) }
        .to raise_error(ArgumentError, 'upload data must be a String or IO')
      expect { bucket.upload_part('file.bin', session_id: 'upload', part_number: 1, data: value) }
        .to raise_error(ArgumentError, 'upload data must be a String or IO')
      expect(transport).not_to have_received(:upload_storage_object)
      expect(transport).not_to have_received(:upload_part)
    end
  end

  it 'rejects malformed object lists' do
    allow(transport).to receive(:list_storage_objects).and_return(response(200, 'objects' => false))

    expect { bucket.list }.to raise_error(Volcano::Error::TransportError, 'invalid storage objects')
  end

  it 'rejects malformed visibility values in object responses' do
    allow(transport).to receive(:move_storage_object)
      .and_return(response(200, object_payload.merge('is_public' => 'false')))

    expect { bucket.move('file.bin', 'moved.bin') }
      .to raise_error(Volcano::Error::TransportError, 'invalid storage boolean')
  end

  it 'rejects malformed object metadata without interpreting arbitrary Ruby values as JSON' do
    invalid = [[], { 42 => 'value' }, { 'nested' => { 'bad' => Object.new } }]

    invalid.each do |metadata|
      allow(transport).to receive(:move_storage_object)
        .and_return(response(200, object_payload.merge('metadata' => metadata)))
      expect { bucket.move('file.bin', 'moved.bin') }.to raise_error(Volcano::Error::TransportError)
    end
  end

  it 'retains nested JSON metadata and the public false visibility value' do
    payload = object_payload.merge('metadata' => { 'nested' => { 'values' => [nil, true, 3, 1.5, 'ok'] } })
    allow(transport).to receive(:update_storage_object_visibility).and_return(response(200, payload))

    object = bucket.update_visibility('file.bin', public: false)

    expect(object.metadata).to eq(payload.fetch('metadata'))
    expect(object.is_public).to be(false)
  end

  it 'rejects metadata that cannot be encoded as JSON' do
    [Float::NAN, Float::INFINITY, -Float::INFINITY, "\xFF".b].each do |value|
      allow(transport).to receive(:move_storage_object)
        .and_return(response(200, object_payload.merge('metadata' => { 'nested' => [value] })))

      expect { bucket.move('file.bin', 'moved.bin') }
        .to raise_error(Volcano::Error::TransportError, 'invalid storage JSON value')
    end
  end

  it 'rejects cyclic or excessively nested metadata without exhausting the Ruby stack' do
    cyclic_hash = {}
    cyclic_hash['self'] = cyclic_hash
    cyclic_array = []
    cyclic_array << cyclic_array
    deeply_nested = 101.times.reduce('value') { |value, _| [value] }

    [cyclic_hash, { 'array' => cyclic_array }, { 'deep' => deeply_nested }].each do |metadata|
      allow(transport).to receive(:move_storage_object)
        .and_return(response(200, object_payload.merge('metadata' => metadata)))

      expect { bucket.move('file.bin', 'moved.bin') }
        .to raise_error(Volcano::Error::TransportError, 'invalid storage JSON value')
    end
  end

  it 'accepts repeated references to an acyclic JSON subtree and snapshots them' do
    subtree = { 'values' => [1, true] }
    metadata = { 'left' => subtree, 'right' => subtree }
    allow(transport).to receive(:move_storage_object)
      .and_return(response(200, object_payload.merge('metadata' => metadata)))

    object = bucket.move('file.bin', 'moved.bin')
    subtree['values'] << 2

    expect(object.metadata).to eq('left' => { 'values' => [1, true] }, 'right' => { 'values' => [1, true] })
    expect(object.metadata).to be_frozen
  end

  it 'rejects a non-object session response' do
    allow(transport).to receive(:create_upload_session).and_return(response(201, []))

    expect { bucket.create_upload_session('file.bin', total_size: 8) }
      .to raise_error(Volcano::Error::TransportError, 'invalid storage response')
  end

  it 'rejects an invalid session identifier' do
    payload = session_payload.merge('session_id' => 42)
    allow(transport).to receive(:create_upload_session).and_return(response(201, payload))

    expect { bucket.create_upload_session('file.bin', total_size: 8) }
      .to raise_error(Volcano::Error::TransportError, 'invalid storage string')
  end

  it 'rejects an invalid part size' do
    payload = session_payload.merge('part_size' => '4')
    allow(transport).to receive(:create_upload_session).and_return(response(201, payload))

    expect { bucket.create_upload_session('file.bin', total_size: 8) }
      .to raise_error(Volcano::Error::TransportError, 'invalid storage integer')
  end

  it 'rejects an invalid expiry' do
    payload = session_payload.merge('expires_at' => nil)
    allow(transport).to receive(:create_upload_session).and_return(response(201, payload))

    expect { bucket.create_upload_session('file.bin', total_size: 8) }
      .to raise_error(Volcano::Error::TransportError, 'invalid storage time')
  end

  it 'preserves an expiry already decoded as Time' do
    expiry = Time.utc(2026, 10, 1)
    payload = session_payload.merge('expires_at' => expiry)
    allow(transport).to receive(:create_upload_session).and_return(response(201, payload))

    expect(bucket.create_upload_session('file.bin', total_size: 8).expires_at).to eq(expiry)
  end

  it 'rejects malformed uploaded parts' do
    allow(transport).to receive(:get_upload_session).and_return(response(200, status_payload.merge('parts' => false)))

    expect { bucket.get_upload_session('file.bin', session_id: 'upload') }
      .to raise_error(Volcano::Error::TransportError, 'invalid upload parts')
  end
end
