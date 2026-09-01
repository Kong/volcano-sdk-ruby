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
    def initialize
      @mutex = Mutex.new
      @generation = 0
      @session = nil
      @callbacks = {}
      @next_callback_id = 0
      @notifications = []
      @dispatching_notifications = false
    end

    def current
      capture.last
    end

    def capture
      @mutex.synchronize { [@generation, @session] }
    end

    def store(session, event: :signed_in)
      dispatch = @mutex.synchronize do
        enqueue_notification(replace(session), event, session)
      end
      drain_notifications if dispatch
    end

    def store_if_current?(session, generation, event: :signed_in)
      dispatch = @mutex.synchronize do
        callbacks = replace_if_current(session, generation)
        return false unless callbacks

        enqueue_notification(callbacks, event, session)
      end
      drain_notifications if dispatch
      true
    end

    def clear_if_current?(generation, event: :signed_out)
      store_if_current?(nil, generation, event: event)
    end

    def subscribe(&callback)
      callback_id, dispatch = @mutex.synchronize do
        id, current = register(callback)
        [id, enqueue_notification([callback], :initial_session, current)]
      end
      drain_notifications if dispatch
      AuthSubscription.new { unsubscribe(callback_id) }
    end

    private

    def replace(session)
      @session = session
      @generation += 1
      @callbacks.values.dup
    end

    def replace_if_current(session, generation)
      return unless generation == @generation

      replace(session)
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
      return false if callbacks.empty?

      @notifications << [callbacks, event, session]
      return false if @dispatching_notifications

      @dispatching_notifications = true
    end

    def drain_notifications
      loop do
        notification = @mutex.synchronize do
          if @notifications.empty?
            @dispatching_notifications = false
            return
          end
          @notifications.shift
        end
        notify(*notification)
      end
    end

    def notify(callbacks, event, session)
      callbacks.each do |callback|
        callback.call(event, session)
      rescue StandardError => e
        Warning.warn("Volcano auth-state callback failed (#{e.class})\n")
      end
    end
  end
end
