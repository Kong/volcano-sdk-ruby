# frozen_string_literal: true

require 'stringio'
require 'support/read_only_upload'

RSpec.describe Volcano::StorageBucket do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:bucket) do
    Volcano::Client.new(anon_key: 'anon', access_token: 'access', _transport: transport).storage.from('assets')
  end
  let(:source) { StringIO.new("prefix\x00\xffbytes".b) }

  def response(status, body)
    Volcano::Transport::Response.new(status: status, body: body, headers: {}, data: nil)
  end

  def object_payload
    { 'id' => 'object', 'bucket_id' => 'assets', 'name' => 'file.bin', 'size' => 7,
      'mime_type' => 'application/octet-stream', 'is_public' => false }
  end

  before do
    source.pos = 6
    allow(transport).to receive_messages(
      create_upload_session: response(201, 'session_id' => 'upload', 'part_size' => 4,
                                           'total_parts' => 2, 'expires_at' => '2026-10-01T00:00:00Z'),
      complete_upload_session: response(200, 'object' => object_payload)
    )
    allow(transport).to receive(:upload_part) do |request:, **|
      response(200, 'part_number' => request.part_number, 'etag' => 'etag', 'size' => request.data.bytesize)
    end
  end

  [IOError, Errno::ESPIPE].each do |error|
    %i[size pos].freeze.each do |operation|
      it "spools remaining bytes when #{operation} raises #{error}" do
        allow(source).to receive(operation).and_raise(error)

        expect(bucket.upload_resumable('file.bin', source).name).to eq('file.bin')
        expect(transport).to have_received(:create_upload_session)
          .with(authorization: 'access', bucket_name: 'assets', request: have_attributes(total_size: 7))
        expect(transport).to have_received(:upload_part)
          .with(authorization: 'access', bucket_name: 'assets',
                request: have_attributes(part_number: 1, data: "\x00\xffby".b))
        expect(transport).to have_received(:upload_part)
          .with(authorization: 'access', bucket_name: 'assets',
                request: have_attributes(part_number: 2, data: 'tes'))
        expect(source).not_to be_closed
      end
    end
  end

  it 'propagates a spool read failure before creating any remote session' do
    allow(source).to receive(:size).and_raise(IOError)
    allow(source).to receive(:read).and_raise(IOError, 'source failed')

    expect { bucket.upload_resumable('file.bin', source) }.to raise_error(IOError, 'source failed')
    expect(transport).not_to have_received(:create_upload_session)
    expect(transport).not_to have_received(:upload_part)
    expect(source).not_to be_closed
  end

  it 'spools a stream whose reported size is not an integer' do
    allow(source).to receive(:size).and_return('unknown')

    expect(bucket.upload_resumable('file.bin', source).name).to eq('file.bin')
    expect(transport).to have_received(:create_upload_session)
      .with(authorization: 'access', bucket_name: 'assets', request: have_attributes(total_size: 7))
    expect(source).not_to be_closed
  end

  it 'spools a stream whose reported position is not an integer' do
    allow(source).to receive(:pos).and_return('unknown')

    expect(bucket.upload_resumable('file.bin', source).name).to eq('file.bin')
    expect(transport).to have_received(:create_upload_session)
      .with(authorization: 'access', bucket_name: 'assets', request: have_attributes(total_size: 7))
  end

  it 'spools a non-seekable readable stream without closing it' do
    stream = SpecSupport::ReadOnlyUpload.new("\x00\xffbytes".b)

    expect(bucket.upload_resumable('file.bin', stream).name).to eq('file.bin')
    expect(transport).to have_received(:create_upload_session)
      .with(authorization: 'access', bucket_name: 'assets', request: have_attributes(total_size: 7))
    expect(stream.read(1)).to be_nil
  end

  it 'aborts when a source ends before the declared part count' do
    allow(source).to receive(:read).and_return(nil)
    allow(transport).to receive(:abort_upload_session).and_return(response(200, {}))

    expect { bucket.upload_resumable('file.bin', source) }
      .to raise_error(IOError, 'upload source ended before completion')
    expect(transport).to have_received(:abort_upload_session)
      .with(authorization: 'access', bucket_name: 'assets', request: have_attributes(session_id: 'upload'))
  end

  it 'rejects unsupported input before creating a remote session' do
    expect { bucket.upload_resumable('file.bin', Object.new) }
      .to raise_error(ArgumentError, 'upload data must be a String or IO')
    expect(transport).not_to have_received(:create_upload_session)
  end
end
