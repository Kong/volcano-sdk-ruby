# frozen_string_literal: true

module Volcano
  # Keeps function resolution and invocation on the captured session lineage.
  class FunctionAuth
    def initialize(client)
      @client = client
      @binding = client.capture_session_binding
      @fallback_token = client.function_token.dup.freeze
    end

    def run
      @binding = @client.auth.__send__(:owned_session_binding, @binding) if @binding.last
      yield(token)
    rescue Error::AuthenticationError => e
      raise unless @binding.last && e.status == 401

      refresh(e)
      yield(token)
    ensure
      validate
    end

    private

    def token
      return @client.auth.__send__(:owned_session_binding, @binding).last.access_token if @binding.last

      validate
      @fallback_token
    end

    def refresh(original)
      # Resolution has released its cache lock before refresh callbacks run.
      @client.auth.__send__(:refresh_captured_session, active_binding)
    rescue Error::SessionChangedError
      raise
    rescue Error::VolcanoError
      raise original
    end

    def validate
      if @binding.last
        @client.auth.__send__(:validate_read_failure, active_binding)
      elsif @client.capture_session_binding[1] != @binding[1]
        raise Error::SessionChangedError
      end
    end

    def active_binding
      generation, owner, session = @binding
      raise Error::SessionChangedError unless session

      [generation, owner, session]
    end
  end
  private_constant :FunctionAuth
end
