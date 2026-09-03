# frozen_string_literal: true

module Volcano
  module Error
    # Base error containing structured Volcano response details.
    class VolcanoError < StandardError
      attr_reader :status, :code, :retry_after

      def initialize(message, status: nil, code: nil, retry_after: nil)
        super(message)
        @status = status
        @code = code
        @retry_after = retry_after
      end
    end

    class AuthenticationError < VolcanoError; end
    class ValidationError < VolcanoError; end
    class NotFoundError < VolcanoError; end
    class ConflictError < VolcanoError; end

    # Raised when an auth response arrives after the client session changes.
    class SessionChangedError < ConflictError
      def initialize(
        message = 'Session changed during authentication operation',
        status: 409,
        code: 'auth_session_changed',
        retry_after: nil
      )
        super
      end
    end

    class RateLimitedError < VolcanoError; end
    class ServerError < VolcanoError; end
    class TransportError < VolcanoError; end
  end
end
