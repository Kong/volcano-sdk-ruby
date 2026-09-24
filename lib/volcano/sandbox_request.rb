# frozen_string_literal: true

require 'securerandom'

module Volcano
  # Immutable addressing and payload for a generated Sandbox operation.
  class SandboxRequest
    def initialize(options)
      @options = options.dup.freeze
      freeze
    end

    def operation = @options.fetch(:operation)
    def resource_id = @options[:resource_id]
    def subject_id = @options[:subject_id]
    def body = @options[:body]
    def request_id = @options[:request_id]
    def timeout = @options.fetch(:timeout, 180)
  end

  # Shared validation and credentials for Sandbox facade operations.
  class SandboxRequests
    UUID = /\A[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}\z/i
    USER_OPERATIONS = %i[get_sandbox_session execute_sandbox_session read_sandbox_session_file
                         write_sandbox_session_file create_sandbox_session_access].freeze
    private_constant :UUID, :USER_OPERATIONS

    def initialize(client, transport)
      @client = client
      @transport = transport
    end

    def call(request, status: 200)
      response = if USER_OPERATIONS.include?(request.operation) && @client.current_session
                   @client.session_request { |token| dispatch(request, token) }
                 else
                   dispatch(request, @client.service_token)
                 end
      Transport.body(response, status)
    end

    def self.identifier(value)
      return value if value.is_a?(String) && UUID.match?(value)

      raise Error::ValidationError, 'Sandbox resource and request IDs must be UUIDs'
    end

    def self.request_id(options)
      identifier(options.fetch(:request_id) { SecureRandom.uuid })
    end

    def self.selector(options)
      if options.key?(:preset) == options.key?(:sandbox_id)
        raise Error::ValidationError, 'Choose exactly one preset or sandbox_id'
      end

      result = options.slice(:region, :preset, :sandbox_id, :memory_mb)
      result[:sandbox_id] = identifier(result[:sandbox_id]) if result.key?(:sandbox_id)
      result
    end

    def self.command(command, options)
      options.slice(:timeout_seconds, :environment).merge(command: command)
    end

    private

    def dispatch(request, token)
      Transport.invoke { @transport.sandbox_request(authorization: token, request: request) }
    end
  end
end
