# frozen_string_literal: true

module Volcano
  # Idempotent handle for an authentication-state subscription.
  class AuthSubscription
    def initialize(&unsubscribe)
      @unsubscribe = unsubscribe
      @mutex = Mutex.new
    end

    def unsubscribe
      callback = @mutex.synchronize do
        current = @unsubscribe
        @unsubscribe = nil
        current
      end
      callback&.call
      nil
    end
  end

  # Owns synchronized local session state and its subscribers.
  class AuthState
    CALLBACK_FAILURES = [Exception].freeze
    private_constant :CALLBACK_FAILURES

    def initialize
      @mutex = Mutex.new
      @generation = 0
      @lineage = 0
      @session = nil
      @callbacks = {}
      @next_callback_id = 0
      @notifications = []
      @dispatching_notifications = false
    end

    def current = capture.last

    def capture = @mutex.synchronize { [@generation, @session] }

    def capture_binding = @mutex.synchronize { [@generation, @lineage, @session] }

    def store(session, event: :signed_in)
      dispatch = @mutex.synchronize do
        enqueue_notification(replace(session, event), event, session)
      end
      drain_notifications if dispatch
    end

    def store_if_current?(session, generation, event: :signed_in, notifications: nil)
      dispatch = @mutex.synchronize do
        callbacks = replace_if_current(session, generation, event)
        return false unless callbacks

        enqueue_notification(callbacks, event, session)
      end
      return true unless dispatch

      notifications ? notifications.push(method(:drain_notifications)) : drain_notifications
      true
    end

    def subscribe(&callback)
      callback_id, dispatch = @mutex.synchronize do
        id, current = register(callback)
        [id, enqueue_notification([id], :initial_session, current)]
      end
      drain_notifications if dispatch
      AuthSubscription.new { unsubscribe(callback_id) }
    end

    private

    def replace(session, event)
      @session = session
      @generation += 1
      @lineage += 1 unless event == :token_refreshed
      @callbacks.keys
    end

    def replace_if_current(session, generation, event)
      return unless generation == @generation

      replace(session, event)
    end

    def register(callback)
      callback_id = @next_callback_id
      @next_callback_id += 1
      @callbacks[callback_id] = callback
      [callback_id, @session]
    end

    def unsubscribe(callback_id)
      @mutex.synchronize { @callbacks.delete(callback_id) }
    end

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
        notify_callback(callback_id, event, session)
      rescue StandardError => e
        Warning.warn("Volcano auth-state callback failed (#{e.class})\n")
      rescue *CALLBACK_FAILURES => e
        unsubscribe(callback_id)
        failure ||= e
      end
      failure
    end

    def notify_callback(callback_id, event, session)
      callback = @mutex.synchronize { @callbacks[callback_id] }
      callback&.call(event, session)
    end
  end
end
