# frozen_string_literal: true

require 'base64'

module Volcano
  # Byte-preserving files inside a Sandbox session.
  class SandboxFiles
    FILE_LIMIT = 8 * 1024 * 1024
    private_constant :FILE_LIMIT

    def initialize(requests, session_id)
      @requests = requests
      @session_id = session_id
    end

    def read(path)
      response = @requests.call(request(:read_sandbox_session_file, { path: path }))
      Base64.strict_decode64(SandboxResponse.text(Transport.json_object(response)['data']))
    end

    def write(path, data)
      raise Error::ValidationError, 'Sandbox files are limited to 8 MiB' if data.bytesize > FILE_LIMIT

      body = { path: path, data: Base64.strict_encode64(data) }
      @requests.call(request(:write_sandbox_session_file, body), status: 204)
      nil
    end

    private

    def request(operation, body)
      SandboxRequest.new(operation: operation, resource_id: @session_id, body: body)
    end
  end
end
