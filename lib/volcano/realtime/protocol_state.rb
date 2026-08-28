# frozen_string_literal: true

module Volcano
  class Realtime
    # Initializes the independent state owned by the realtime protocol.
    module ProtocolState
      private

      def initialize_state
        initialize_request_state
        initialize_callback_state
        initialize_subscription_state
      end

      def initialize_request_state
        @next_id = 0
        @pending = {}
        @write_lock = Async::Semaphore.new(1)
        @closed_error = nil
      end

      def initialize_callback_state
        @callback_queue = Async::Queue.new
        @callback_stopping = @closed = false
      end

      def initialize_subscription_state
        @subscription_lock = Async::Semaphore.new(1)
        @publication_handlers = Hash.new { |hash, key| hash[key] = [] }
        @subscriptions = Set.new
      end
    end
  end
end
