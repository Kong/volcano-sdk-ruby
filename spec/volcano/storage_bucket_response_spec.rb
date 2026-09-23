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
