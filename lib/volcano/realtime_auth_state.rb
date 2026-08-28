# frozen_string_literal: true

module Volcano
  # Invalidates realtime work authenticated by a replaced client session.
  module RealtimeAuthState
    def reset_authentication
      @protocol_lock ? @protocol_lock.acquire { reset_protocol } : reset_protocol
    rescue StandardError => e
      warn(public_error(e).message)
    end

    private

    def reset_protocol
      protocol = @protocol
      @protocol = nil
      begin
        protocol&.close
      ensure
        @channels.each_value(&:reset_authentication)
      end
    end
  end
  private_constant :RealtimeAuthState
end
