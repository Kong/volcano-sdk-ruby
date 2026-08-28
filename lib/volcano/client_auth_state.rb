# frozen_string_literal: true

require 'monitor'

# Public namespace for Volcano SDK client state.
module Volcano
  # Owns one client's in-memory auth state and listener registry.
  module ClientAuthState
    def commit_auth(session, user)
      @auth_state_monitor.synchronize do
        @current_session = session
        @current_user = user
        reset_realtime_authentication
        notify_auth_listeners
      end
    end

    def store_user(user)
      @auth_state_monitor.synchronize do
        @current_user = user
        notify_auth_listeners
      end
    end

    def clear_auth
      @auth_state_monitor.synchronize do
        @current_session = nil
        @current_user = nil
        reset_realtime_authentication
        notify_auth_listeners
      end
    end

    def subscribe_auth(listener)
      @auth_state_monitor.synchronize do
        listener_id = @next_auth_listener_id
        @next_auth_listener_id += 1
        @auth_listeners[listener_id] = listener
        notify_auth_listener(listener) unless @current_session && @current_user.nil?
        build_unsubscribe(listener_id)
      end
    end

    private

    def initialize_auth_state(access_token, refresh_token)
      @auth_state_monitor = Monitor.new
      @current_session = initial_session(access_token, refresh_token)
      @current_user = nil
      @auth_listeners = {}
      @next_auth_listener_id = 0
    end

    def build_unsubscribe(listener_id)
      removed = false
      proc do
        next if removed

        @auth_state_monitor.synchronize do
          @auth_listeners.delete(listener_id)
          removed = true
        end
      end
    end

    def notify_auth_listeners
      @auth_listeners.each_value { |listener| notify_auth_listener(listener) }
    end

    def notify_auth_listener(listener)
      listener.call(@current_user)
    rescue StandardError
      warn('Volcano auth-state listener failed')
    end

    def reset_realtime_authentication
      @realtime&.reset_authentication
    end
  end
  private_constant :ClientAuthState
end
