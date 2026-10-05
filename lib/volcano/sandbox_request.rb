# frozen_string_literal: true

require 'securerandom'
require 'time'

module Volcano
  # Immutable addressing and payload for a generated Sandbox operation.
  class SandboxRequest
    def initialize(options)
      @options = options.dup
      body = options[:body]
      @options[:body] = ImmutableRequestValue.capture(body) if body
      @options.freeze
      freeze
    end

    def operation = @options.fetch(:operation)
    def resource_id = @options[:resource_id]
    def subject_id = @options[:subject_id]
    def body = @options[:body]
    def request_id = @options[:request_id]
    def timeout = @options.fetch(:timeout, 0)
  end

  # Shared validation and credentials for Sandbox facade operations.
  class SandboxRequests
    UUID = /\A[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}\z/i
    USER_OPERATIONS = %i[get_sandbox_session execute_sandbox_session read_sandbox_session_file
                         write_sandbox_session_file create_sandbox_session_access].freeze
    private_constant :UUID, :USER_OPERATIONS

    def initialize(client, transport, service_only: false)
      @client = client
      @transport = transport
      @service_only = service_only
    end

    def service_scope = SandboxRequests.new(@client, @transport, service_only: true)

    def call(request, status: 200)
      response = if request.operation == :list_sandbox_presets
                   dispatch(request, '')
                 elsif user_request?(request)
                   @client.session_request { |token| dispatch(request, token) }
                 else
                   dispatch(request, @client.service_token)
                 end
      Transport.body(response, status)
    end

    def self.expiry(value)
      parsed = value.is_a?(Time) ? value : Time.iso8601(value)
      parsed.getutc.iso8601
    rescue ArgumentError
      raise Error::ValidationError, 'Sandbox grant expiry must be a Time or ISO8601 timestamp'
    end

    def self.identifier(value)
      return value.dup.freeze if value.is_a?(String) && UUID.match?(value)

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

    def user_request?(request)
      !@service_only && USER_OPERATIONS.include?(request.operation) && !@client.current_session.nil?
    end

    def dispatch(request, token)
      Transport.invoke { @transport.sandbox_request(authorization: token, request: request) }
    end
  end
end
