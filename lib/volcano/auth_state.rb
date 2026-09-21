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

    def initialize(session: nil)
      @mutex = Mutex.new
      @generation = 0
      @lineage = SessionOperations.new
      @session = session
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

    def store_if_current?(session, generation, event: :signed_in, notifications: nil, lineage: nil)
      dispatch = @mutex.synchronize do
        return false unless current_binding?(generation, lineage)
        return true if session.nil? && @session.nil?

        enqueue_notification(replace(session, event, verified_pair: session), event, session)
      end
      return true unless dispatch

      dispatch_notifications(notifications)
      true
    end

    def update_user_if_current?(user, generation)
      @mutex.synchronize do
        return false unless generation == @generation && @session

        @session = SessionCredentials.with_user(@session, user)
        true
      end
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

    def current_binding?(generation, lineage) = lineage.nil? ? generation == @generation : lineage == @lineage

    def dispatch_notifications(queue) = queue ? queue.push(method(:drain_notifications)) : drain_notifications

    def replace(session, event, verified_pair: nil)
      SessionCredentials.validate_refresh(@session, session) if event == :token_refreshed
      @session = session
      @generation += 1
      @lineage.clear_local_credentials unless session
      @lineage = SessionOperations.new(verified_pair) if session && event != :token_refreshed
      @callbacks.keys
    end

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
end
