# frozen_string_literal: true

module Volcano
  # Invalidates realtime work authenticated by a replaced client session.
  module RealtimeAuthState
    def reset_authentication
      return if @protocol.nil? && @channels.empty?

      with_authentication_lock { reset_authentication_locked }
    rescue StandardError => e
      warn(public_error(e).message)
    end

    private

    def with_authentication_lock(&)
      authentication_lock.acquire(&)
    end

    def authentication_lock
      return @authentication_lock if @authentication_lock

      @authentication_lock_creation.synchronize do
        require 'async/semaphore'
        @authentication_lock ||= Async::Semaphore.new(1)
      end
    end

    def reset_authentication_locked
      channels = @channels.values
      protocol = @protocol_lock ? @protocol_lock.acquire { detach_protocol } : detach_protocol
      protocol&.close
    ensure
      channels&.each(&:reset_authentication)
    end

    def detach_protocol
      protocol = @protocol
      @protocol = nil
      protocol
    end
  end
  private_constant :RealtimeAuthState
end
