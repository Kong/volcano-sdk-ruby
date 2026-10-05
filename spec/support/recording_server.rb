# frozen_string_literal: true

require 'json'
require 'socket'

# A local HTTP server that answers from a caller-supplied block and records
# what it received, so specs can assert which host a request actually reached.
class RecordingServer
  Request = Struct.new(:target, :body, :authorization, :http_method)

  def initialize(&respond)
    @server = TCPServer.new('127.0.0.1', 0)
    # Connections are served one at a time, so the backlog has to hold every
    # caller an example starts at once or the rest see a reset.
    @server.listen(64)
    @requests = []
    @lock = Mutex.new
    @respond = respond
    @worker = Thread.new { serve }
  end

  def url
    "http://127.0.0.1:#{@server.local_address.ip_port}"
  end

  def requests
    @lock.synchronize { @requests.dup }
  end

  def targets
    requests.map(&:target)
  end

  def close
    @worker.kill
    @worker.join
    @server.close
  end

  private

  def serve
    loop { handle(@server.accept) }
  rescue IOError, Errno::EBADF
    nil
  end

  def handle(socket)
    request = read_request(socket)
    @lock.synchronize { @requests << request }
    status, payload, extra = @respond.call(request.target)
    body = status == 204 ? '' : JSON.generate(payload)
    write_response(socket, status, body, extra || {})
  ensure
    socket&.close
  end

  def write_response(socket, status, body, extra = {})
    reason = status == 200 ? 'OK' : 'Not Found'
    # The server stamps the version on every response, errors included, so a
    # spec that omits it would accept a client keying a retry off its absence.
    headers = { 'X-Volcano-Version' => 'test-build' }.merge(extra)
    stamped = headers.map { |name, value| "#{name}: #{value}\r\n" }.join
    socket.write("HTTP/1.1 #{status} #{reason}\r\nContent-Type: application/json\r\n" \
                 "Content-Length: #{body.bytesize}\r\nConnection: close\r\n#{stamped}\r\n#{body}")
  end

  def read_request(socket)
    lines = []
    lines << socket.readline until lines.last == "\r\n"
    length = Integer(header(lines, 'content-length') || '0', 10)
    Request.new(
      lines.first.split[1],
      length.positive? ? socket.read(length) : nil,
      header(lines, 'authorization'),
      lines.first.split.first
    )
  end

  def header(lines, name)
    line = lines.find { |candidate| candidate.downcase.start_with?("#{name}:") }
    return nil if line.nil?

    line.split(':', 2).last.strip
  end
end
