# frozen_string_literal: true

# Public namespace for Volcano SDK client state.
module Volcano
  # Owns one client's in-memory auth state and listener registry.
  module ClientAuthState
    def commit_auth(session, user)
      @current_session = session
      @current_user = user
      notify_auth_listeners
    end

    def store_user(user)
      @current_user = user
      notify_auth_listeners
    end

    def clear_auth
      @current_session = nil
      @current_user = nil
      notify_auth_listeners
    end

    def subscribe_auth(listener)
      listener_id = @next_auth_listener_id
      @next_auth_listener_id += 1
      @auth_listeners[listener_id] = listener
      notify_auth_listener(listener)
      build_unsubscribe(listener_id)
    end

    private

    def initialize_auth_state(access_token, refresh_token)
      @current_session = initial_session(access_token, refresh_token)
      @current_user = nil
      @auth_listeners = {}
      @next_auth_listener_id = 0
    end

    def build_unsubscribe(listener_id)
      removed = false
      proc do
        next if removed

        @auth_listeners.delete(listener_id)
        removed = true
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
  end
  private_constant :ClientAuthState
end
