# frozen_string_literal: true

require 'spec_helper'
require 'socket'
require 'stringio'

RSpec.describe Volcano::StorageBucket do
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
    length = headers.find { |line| line.match?(/\Acontent-length:/i) }.split(':').last.to_i
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
end
