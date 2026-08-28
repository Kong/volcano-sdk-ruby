# frozen_string_literal: true

module Volcano
  # Invalidates realtime work authenticated by a replaced client session.
  module RealtimeAuthState
    def reset_authentication
      protocol = @protocol_lock ? @protocol_lock.acquire { detach_protocol } : detach_protocol
      begin
        protocol&.close
      ensure
        @channels.each_value(&:reset_authentication)
      end
    rescue StandardError => e
      warn(public_error(e).message)
    end

    private

    def detach_protocol
      protocol = @protocol
      @protocol = nil
      protocol
    end
  end
  private_constant :RealtimeAuthState
end
