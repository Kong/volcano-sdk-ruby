# frozen_string_literal: true

module Volcano
  module Error
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
    class RateLimitedError < VolcanoError; end
    class ServerError < VolcanoError; end
    class TransportError < VolcanoError; end
  end
end
