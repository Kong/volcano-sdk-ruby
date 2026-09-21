# frozen_string_literal: true

module Volcano
  # Queues auth events under the state mutex and invokes subscribers outside it.
  module AuthStateNotifications
    CALLBACK_FAILURES = [Exception].freeze
    private_constant :CALLBACK_FAILURES

    private

    def register(callback)
      @next_callback_id += 1
      @callbacks[@next_callback_id] = callback
      [@next_callback_id, @session]
    end

    def unsubscribe(callback_id) = @mutex.synchronize { @callbacks.delete(callback_id) }

    def enqueue_notification(callbacks, event, session)
      return false if event.nil? || callbacks.empty?

      @notifications << [callbacks, event, session]
      return false if @dispatching_notifications

      @dispatching_notifications = true
    end

    def drain_notifications
      failure = nil
      loop do
        notification = next_notification
        break unless notification

        current_failure = notify(*notification)
        failure ||= current_failure
      end
      raise failure if failure
    end

    def next_notification
      @mutex.synchronize do
        if @notifications.empty?
          @dispatching_notifications = false
          return
        end
        @notifications.shift
      end
    end

    def notify(callback_ids, event, session)
      failure = nil
      callback_ids.each do |callback_id|
        @mutex.synchronize { @callbacks[callback_id] }&.call(event, session)
      rescue StandardError => e
        Warning.warn("Volcano auth-state callback failed (#{e.class})\n")
      rescue *CALLBACK_FAILURES => e
        unsubscribe(callback_id)
        failure ||= e
      end
      failure
    end
  end
  private_constant :AuthStateNotifications
end
