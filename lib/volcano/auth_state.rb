# frozen_string_literal: true

require_relative 'auth_state_notifications'

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
    include AuthStateNotifications

    def initialize(session: nil)
      @mutex = Mutex.new
      @generation = 0
      @lineage = SessionOperations.new
      @session = session
      @rejected_refresh = nil
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

    def reject_refresh_if_current?(generation, notifications: nil)
      dispatch = @mutex.synchronize do
        return false unless generation == @generation && @session

        # Publish rejection and credential removal as one synchronized transition.
        @rejected_refresh = [generation, @lineage]
        enqueue_notification(replace(nil, :signed_out), :signed_out, nil)
      end
      dispatch_notifications(notifications) if dispatch
      true
    end

    def refresh_rejected?(generation, lineage)
      @mutex.synchronize { @rejected_refresh == [generation, lineage] }
    end

    def update_user_if_current?(user, generation)
      @mutex.synchronize do
        current = @session
        return false unless generation == @generation && current

        @session = SessionCredentials.with_user(current, user)
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
  end
end
