# frozen_string_literal: true

module Volcano
  # Validates the client methods that storage uses for session-scoped requests.
  class StorageSessionAdapter
    def initialize(client)
      @client = client
    end

    def capture_session_binding
      binding = storage_binding_array(@client.method(:capture_session_binding).call)
      generation, owner, session = binding
      [storage_generation(generation), storage_owner(owner), storage_session(session)]
    end

    def session_token
      token = @client.method(:session_token).call
      raise Error::TransportError, 'invalid storage session token' unless token.is_a?(String)

      token
    end

    def session_request(binding:, &)
      method_name = :session_request
      response = @client.public_send(method_name, binding: binding) do |token|
        raise Error::TransportError, 'invalid storage session token' unless token.is_a?(String)

        yield token
      end
      raise Error::TransportError, 'invalid storage session response' unless response.is_a?(Transport::Response)

      response
    end

    private

    def storage_binding_array(value)
      raise Error::TransportError, 'invalid storage session binding' unless value.is_a?(Array) && value.size == 3

      value
    end

    def storage_generation(value)
      raise Error::TransportError, 'invalid storage session binding' unless value.is_a?(Integer)

      value
    end

    def storage_owner(value)
      raise Error::TransportError, 'invalid storage session binding' unless value.is_a?(SessionOperations)

      value
    end

    def storage_session(value)
      raise Error::TransportError, 'invalid storage session binding' unless value.nil? || value.is_a?(Session)

      value
    end
  end
end
