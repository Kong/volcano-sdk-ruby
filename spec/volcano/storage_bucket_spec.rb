# frozen_string_literal: true

require 'spec_helper'
require 'support/session_fixtures'
require 'socket'
require 'stringio'

RSpec.describe Volcano::StorageBucket do
  include SessionFixtures

  def capture_upload(content_type)
    server = TCPServer.new('127.0.0.1', 0)
    worker = Thread.new { receive_upload(server) }
    client = authenticated_client("http://127.0.0.1:#{server.local_address.ip_port}")
    source = upload_sample(client, content_type)
    [worker.value, source.closed?]
  ensure
    worker&.kill&.join
    server&.close
  end

  def upload_sample(client, content_type)
    source = StringIO.new("skip-hello\x00\xff".b)
    source.pos = 5
    options = content_type ? { content_type: content_type } : {}
    client.storage.from('assets').upload('payload.bin', source, **options)
    source
  end

  def authenticated_client(api_url = 'http://127.0.0.1:1')
    Volcano::Client.new(api_url: api_url, anon_key: 'anon', timeout: 2).tap do |client|
      client.auth.current_session = Volcano::Session.new(
        access_token: 'access', refresh_token: 'refresh', user_id: 'user'
      )
    end
  end

  def receive_upload(server)
    socket = server.accept
    headers = []
    headers << socket.readline until headers.last == "\r\n"
    length = Integer(headers.find { |line| line.match?(/\Acontent-length:/i) }.split(':').last, 10)
    body = socket.read(length)
    response = upload_response
    socket.write("HTTP/1.1 201 Created\r\nContent-Type: application/json\r\n" \
                 "Content-Length: #{response.bytesize}\r\nConnection: close\r\n\r\n#{response}")
    [headers.join, body]
  ensure
    socket&.close
  end

  def upload_response
    JSON.generate(
      id: '00000000-0000-4000-8000-000000000020', bucket_id: '00000000-0000-4000-8000-000000000030',
      name: 'payload.bin', size: 7, mime_type: 'application/octet-stream', is_public: false,
      metadata: {}, owner_id: '00000000-0000-4000-8000-000000000010',
      created_at: '2026-09-08T12:00:00Z', updated_at: '2026-09-08T12:00:00Z'
    )
  end

  [nil, 'image/png', 'text/plain; charset=utf-8'].each do |content_type|
    it "sends the multipart file type #{content_type.inspect}" do
      (headers, body), closed = capture_upload(content_type)

      expect(headers).to match(%r{Content-Type: multipart/form-data; boundary=}i)
      expect(headers).to include('POST /storage/assets/payload.bin HTTP/1.1', 'Authorization: Bearer access')
      expect(body).to include("Content-Type: #{content_type || 'application/octet-stream'}\r\n")
      expect(body).to include('name="file"', "\r\n\r\nhello\x00\xff\r\n".b)
      expect(closed).to be(false)
    end
  end

  ['', ' ', "text/plain\r\nX-Bad: yes", "x\x00y", 1].each do |content_type|
    it "rejects invalid content_type #{content_type.inspect} before reading" do
      client = authenticated_client
      source = StringIO.new('unchanged')

      expect { client.storage.from('assets').upload('payload.bin', source, content_type: content_type) }
        .to raise_error(ArgumentError, /content_type/)
      expect(source.pos).to eq(0)
    end
  end

  context 'when authentication expires' do
    let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
    let(:client) { Volcano::Client.new(anon_key: 'anon', _transport: transport) }
    let(:bucket) { client.storage.from('assets') }

    before do
      client.auth.current_session = Volcano::Session.new(access_token('old'), 'old-refresh', 'user')
      allow(transport).to receive(:auth_refresh).and_return(refresh_response)
    end

    def response(status, body = { 'error' => 'storage denied' })
      Volcano::Transport::Response.new(status:, body:, headers: {}, data: 'bytes')
    end

    def refresh_response
      response(200, 'access_token' => access_token('new'), 'refresh_token' => 'new-refresh',
                    'user' => { 'id' => 'user' })
    end

    def object_payload
      { 'id' => 'object', 'bucket_id' => 'bucket', 'name' => 'file.bin', 'size' => 7,
        'mime_type' => 'application/octet-stream', 'is_public' => false }
    end

    def session_payload
      { 'session_id' => 'upload', 'part_size' => 7, 'total_parts' => 1,
        'expires_at' => '2026-09-18T00:00:00Z', 'created_at' => '2026-09-17T00:00:00Z',
        'status' => 'uploading', 'path' => 'file.bin', 'content_type' => 'application/octet-stream',
        'total_size' => 7, 'parts_uploaded' => 0, 'bytes_uploaded' => 0, 'parts' => [] }
    end

    def success_payload
      object_payload.merge(session_payload).merge(
        'part_number' => 1, 'etag' => 'part-1', 'object' => object_payload,
        'objects' => [object_payload], 'next_cursor' => ''
      )
    end

    {
      upload: [:upload_storage_object, ['file.bin', 'hello'], {}, 201],
      download: [:download_storage_object, ['file.bin'], {}, 200],
      list: [:list_storage_objects, ['file'], { limit: 2, cursor: 'next' }, 200],
      remove: [:delete_storage_object, ['file.bin'], {}, 200],
      move: [:move_storage_object, %w[file.bin moved.bin], {}, 200],
      copy: [:copy_storage_object, %w[file.bin copy.bin], {}, 201],
      update_visibility: [:update_storage_object_visibility, ['file.bin'], { public: true }, 200],
      create_upload_session: [:create_upload_session, ['file.bin'], { total_size: 7 }, 201],
      upload_part: [:upload_part, ['file.bin'], { session_id: 'upload', part_number: 1, data: 'hello' }, 200],
      complete_upload_session: [:complete_upload_session, ['file.bin'], { session_id: 'upload' }, 200],
      get_upload_session: [:get_upload_session, ['file.bin'], { session_id: 'upload' }, 200],
      abort_upload_session: [:abort_upload_session, ['file.bin'], { session_id: 'upload' }, 200]
    }.each do |operation, (endpoint, args, options, status)|
      context "when #{operation} rejects the access token" do
        let(:perform) { -> { bucket.public_send(operation, *args, **options) } }

        before { allow(transport).to receive(endpoint).and_return(response(401), response(status, success_payload)) }

        it 'refreshes once and replays the same request' do
          calls = []
          allow(transport).to receive(endpoint) do |**kwargs|
            calls << kwargs
            calls.one? ? response(401) : response(status, success_payload)
          end
          perform.call

          expect(transport).to have_received(:auth_refresh)
            .with(authorization: 'anon', refresh_token: 'old-refresh').once
          expect(calls.map { |call| call.fetch(:authorization) }).to eq([access_token('old'), access_token('new')])
          expect(calls.last.except(:authorization)).to eq(calls.first.except(:authorization))
        end

        it 'returns the second rejection without another retry' do
          allow(transport).to receive(endpoint).and_return(response(401))

          expect { perform.call }.to raise_error(Volcano::Error::AuthenticationError, 'storage denied')
          expect(transport).to have_received(endpoint).twice
          expect(transport).to have_received(:auth_refresh).once
        end

        [401, 503].freeze.each do |refresh_status|
          it "preserves the original failure after refresh HTTP #{refresh_status}" do
            allow(transport).to receive(:auth_refresh).and_return(response(refresh_status, 'error' => 'refresh failed'))

            expect { perform.call }.to raise_error(Volcano::Error::AuthenticationError, 'storage denied')
            expect(transport).to have_received(endpoint).once
            expect(client.current_session.nil?).to eq(refresh_status == 401)
          end
        end

        it 'does not replay under a replacement session' do
          replacement = Volcano::Session.new('replacement', 'new-refresh', 'other')
          allow(transport).to receive(:auth_refresh) do
            client.auth.current_session = replacement
            refresh_response
          end

          expect { perform.call }.to raise_error(Volcano::Error::SessionChangedError)
          expect(client.current_session).to eq(replacement)
          expect(transport).to have_received(endpoint).once
        end

        [403, 503].freeze.each do |failure_status|
          it "does not refresh HTTP #{failure_status}" do
            allow(transport).to receive(endpoint).and_return(response(failure_status))

            expect { perform.call }.to raise_error(Volcano::Error::VolcanoError, 'storage denied')
            expect(transport).to have_received(endpoint).once
            expect(transport).not_to have_received(:auth_refresh)
          end
        end

        it 'does not replay ambiguous transport failures' do
          allow(transport).to receive(endpoint).and_raise(Timeout::Error)

          expect { perform.call }.to raise_error(Volcano::Error::TransportError)
          expect(transport).to have_received(endpoint).once
          expect(transport).not_to have_received(:auth_refresh)
        end
      end
    end

    it 'replays the remaining stream bytes after refreshing' do
      calls = []
      source = StringIO.new("skip-hello\x00\xff".b)
      source.pos = 5
      allow(transport).to receive(:upload_storage_object) do |**kwargs|
        calls << kwargs
        calls.one? ? response(401) : response(201, object_payload)
      end
      bucket.upload('file.bin', source)

      expect(calls.map { |call| call.fetch(:data) }).to eq(["hello\x00\xff".b] * 2)
      expect(source).not_to be_closed
    end

    it 'refreshes only the rejected path and then reuses rotated credentials' do
      calls = []
      allow(transport).to receive(:delete_storage_object) do |**kwargs|
        calls << [kwargs.fetch(:path), kwargs.fetch(:authorization)]
        calls.size == 2 ? response(401) : response(200, {})
      end
      bucket.remove(%w[first second third])

      expect(calls).to eq([
                            ['first', access_token('old')],
                            ['second', access_token('old')],
                            ['second', access_token('new')],
                            ['third', access_token('new')]
                          ])
    end

    it 'retains the session that owned the upload source before reading' do
      replacement = Volcano::Session.new('replacement', 'replacement-refresh', 'other')
      source = StringIO.new('private')
      allow(source).to receive(:read) do
        client.auth.current_session = replacement
        'private'
      end
      allow(transport).to receive(:upload_storage_object).and_return(response(201, object_payload))

      expect { bucket.upload('file.bin', source) }.to raise_error(Volcano::Error::SessionChangedError)
      expect(client.current_session).to eq(replacement)
      expect(transport).not_to have_received(:upload_storage_object)
    end

    it 'refreshes each rejected path from its current generation' do
      calls = []
      allow(transport).to receive(:delete_storage_object) do |**kwargs|
        calls << kwargs.fetch(:authorization)
        calls.size.odd? ? response(401) : response(200, {})
      end
      rotated = response(200, 'access_token' => access_token('second'), 'refresh_token' => 'second-refresh',
                              'user' => { 'id' => 'user' })
      allow(transport).to receive(:auth_refresh).and_return(refresh_response, rotated)
      bucket.remove(%w[first second])

      expect(calls).to eq([access_token('old'), access_token('new'), access_token('new'), access_token('second')])
      expect(transport).to have_received(:auth_refresh).with(authorization: 'anon', refresh_token: 'new-refresh').once
    end

    it 'stops deleting when a different session is adopted between paths' do
      replacement = Volcano::Session.new('replacement', 'replacement-refresh', 'other')
      allow(transport).to receive(:delete_storage_object) do
        client.auth.current_session = replacement
        response(200, {})
      end

      expect { bucket.remove(%w[first second]) }.to raise_error(Volcano::Error::SessionChangedError)
      expect(client.current_session).to eq(replacement)
      expect(transport).to have_received(:delete_storage_object).once
    end
  end
end
