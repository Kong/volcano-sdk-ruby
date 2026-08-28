# frozen_string_literal: true

require 'monitor'
require_relative 'client_auth_notifications'

# Public namespace for Volcano SDK client state.
module Volcano
  # Owns one client's in-memory auth state and listener registry.
  module ClientAuthState
    include ClientAuthNotifications

    def commit_auth(session, user)
      dispatch = @auth_state_monitor.synchronize do
        @current_session = session
        @current_user = user
        reset_realtime_authentication
        enqueue_auth_notification(@auth_listeners.values, user)
      end
      drain_auth_notifications if dispatch
    end

    def store_user(user)
      dispatch = @auth_state_monitor.synchronize do
        @current_user = user
        enqueue_auth_notification(@auth_listeners.values, user)
      end
      drain_auth_notifications if dispatch
    end

    def clear_user
      dispatch = @auth_state_monitor.synchronize do
        @current_user = nil
        enqueue_auth_notification(@auth_listeners.values, nil)
      end
      drain_auth_notifications if dispatch
    end

    def clear_auth
      dispatch = @auth_state_monitor.synchronize do
        @current_session = nil
        @current_user = nil
        reset_realtime_authentication
        enqueue_auth_notification(@auth_listeners.values, nil)
      end
      drain_auth_notifications if dispatch
    end

    def subscribe_auth(listener)
      listener_id, dispatch = @auth_state_monitor.synchronize do
        listener_id = @next_auth_listener_id
        @next_auth_listener_id += 1
        @auth_listeners[listener_id] = listener
        notify = !(@current_session && @current_user.nil?)
        dispatch = enqueue_auth_notification([listener], @current_user) if notify
        [listener_id, dispatch]
      end
      drain_auth_notifications if dispatch
      build_unsubscribe(listener_id)
    end

    private

    def initialize_auth_state(access_token, refresh_token)
      @auth_state_monitor = Monitor.new
      @current_session = initial_session(access_token, refresh_token)
      @current_user = nil
      @auth_listeners = {}
      @next_auth_listener_id = 0
      @auth_notifications = []
      @dispatching_auth_notifications = false
      @auth_notification_deferral_depth = 0
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

    def reset_realtime_authentication
      @realtime&.reset_authentication
    end
  end
  private_constant :ClientAuthState
end
