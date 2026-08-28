# frozen_string_literal: true

require 'monitor'

# Public namespace for Volcano SDK client state.
module Volcano
  # Owns one client's in-memory auth state and listener registry.
  module ClientAuthState
    def commit_auth(session, user)
      listeners = @auth_state_monitor.synchronize do
        @current_session = session
        @current_user = user
        reset_realtime_authentication
        @auth_listeners.values
      end
      notify_auth_listeners(listeners, user)
    end

    def store_user(user)
      listeners = @auth_state_monitor.synchronize do
        @current_user = user
        @auth_listeners.values
      end
      notify_auth_listeners(listeners, user)
    end

    def clear_auth
      listeners = @auth_state_monitor.synchronize do
        @current_session = nil
        @current_user = nil
        reset_realtime_authentication
        @auth_listeners.values
      end
      notify_auth_listeners(listeners, nil)
    end

    def subscribe_auth(listener)
      listener_id, immediate_user, notify_immediately = @auth_state_monitor.synchronize do
        listener_id = @next_auth_listener_id
        @next_auth_listener_id += 1
        @auth_listeners[listener_id] = listener
        [listener_id, @current_user, !(@current_session && @current_user.nil?)]
      end
      notify_auth_listener(listener, immediate_user) if notify_immediately
      build_unsubscribe(listener_id)
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

    def notify_auth_listeners(listeners, user)
      listeners.each { |listener| notify_auth_listener(listener, user) }
      nil
    end

    def notify_auth_listener(listener, user)
      listener.call(user)
    rescue StandardError
      warn('Volcano auth-state listener failed')
    end

    def reset_realtime_authentication
      @realtime&.reset_authentication
    end
  end
  private_constant :ClientAuthState
end
