# frozen_string_literal: true

# Public namespace for Volcano SDK client state.
module Volcano
  # Serializes auth notifications without invoking listeners under operation locks.
  module ClientAuthNotifications
    def defer_auth_notifications(operation_monitor)
      dispatch = false
      operation_monitor.synchronize do
        begin_auth_notification_deferral
        return yield
      ensure
        dispatch = finish_auth_notification_deferral
      end
    ensure
      drain_auth_notifications if dispatch
    end

    private

    def begin_auth_notification_deferral
      @auth_state_monitor.synchronize { @auth_notification_deferral_depth += 1 }
    end

    def finish_auth_notification_deferral
      @auth_state_monitor.synchronize do
        @auth_notification_deferral_depth -= 1
        begin_deferred_auth_dispatch
      end
    end

    def enqueue_auth_notification(listeners, user)
      @auth_notifications << [listeners, user]
      return false if @dispatching_auth_notifications || @auth_notification_deferral_depth.positive?

      @dispatching_auth_notifications = true
    end

    def begin_deferred_auth_dispatch
      return false if @auth_notification_deferral_depth.positive?
      return false if @dispatching_auth_notifications || @auth_notifications.empty?

      @dispatching_auth_notifications = true
    end

    def drain_auth_notifications
      loop do
        notification = @auth_state_monitor.synchronize { shift_auth_notification }
        break unless notification

        listeners, user = notification
        listeners.each { |listener| notify_auth_listener(listener, user) }
      end
      nil
    end

    def shift_auth_notification
      @dispatching_auth_notifications = false if @auth_notifications.empty?
      @auth_notifications.shift
    end

    def notify_auth_listener(listener, user)
      listener.call(user)
    rescue StandardError
      warn('Volcano auth-state listener failed')
    end
  end
  private_constant :ClientAuthNotifications
end
