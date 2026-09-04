# frozen_string_literal: true

require 'json'
require_relative 'protocol_dispatch'
require_relative 'protocol_publication_dispatch'
require_relative 'protocol_recovery_dispatch'
require_relative 'protocol_lifecycle'
require_relative 'protocol_recovery'

module Volcano
  class Realtime
    # Error returned by the realtime server for a command.
    class ServerError < StandardError
      attr_reader :code

      def initialize(message, code: nil)
        super(message)
        @code = code.is_a?(String) ? code.dup.freeze : code
      end
    end

    class ClosedError < StandardError; end
    class DuplicateSubscriptionError < StandardError; end
    class PendingLimitError < StandardError; end
    class RequestTimeoutError < StandardError; end

    # Implements the Centrifuge request and publication protocol.
    class Protocol
      include ProtocolDispatch
      include ProtocolPublicationDispatch
      include ProtocolRecoveryDispatch
      include Lifecycle
      include ProtocolRecovery

      Failure = Data.define(:error)
      Events = Data.define(:on_close, :on_error, :on_failure)
      DEFAULT_REQUEST_TIMEOUT = 10
      DEFAULT_MAX_PENDING = 128
      DEFAULT_MAX_CALLBACK_QUEUE = 128
      LIMIT_KEYS = %i[request_timeout max_pending max_callback_queue].freeze

      def self.connect(id:, token:) = { 'id' => id, 'connect' => { 'token' => token } }

      def self.subscribe(id:, channel:, recovery: nil, recoverable: false, join_leave: false)
        options = { 'channel' => channel }
        if recovery
          options.merge!('recover' => true, 'positioned' => true, 'recoverable' => true)
          options['epoch'] = recovery.fetch(:epoch) if recovery.key?(:epoch)
          options['offset'] = recovery.fetch(:offset) if recovery.key?(:offset)
        end
        options['recoverable'] = true if recoverable
        options['join_leave'] = true if join_leave
        { 'id' => id, 'subscribe' => options }
      end

      def self.publish(id:, channel:, data:) = { 'id' => id, 'publish' => { 'channel' => channel, 'data' => data } }

      def self.unsubscribe(id:, channel:) = { 'id' => id, 'unsubscribe' => { 'channel' => channel } }

      def self.presence(id:, channel:) = { 'id' => id, 'presence' => { 'channel' => channel } }

      def initialize(
        socket:,
        task: nil,
        secrets: [],
        events: nil,
        **limits
      )
        load_async
        @socket = socket
        @secrets = secrets.freeze
        @events = events
        configure_limits(limits)
        initialize_state
        start_tasks(task || Async::Task.current)
      end

      def connect(token:)
        result = request { |id| self.class.connect(id: id, token: token) }
        ensure_open!
        @connected = true
        result
      end

      def subscribe(channel:, recovery: nil, recoverable: false, join_leave: false)
        @subscription_lock.acquire do
          ensure_open!
          raise DuplicateSubscriptionError, "already subscribed to #{channel}" if @subscriptions.include?(channel)

          result = request(on_reply: recovery_result_handler(channel, recovery)) do |id|
            self.class.subscribe(
              id: id,
              channel: channel,
              recovery: recovery,
              recoverable: recoverable,
              join_leave: join_leave
            )
          end
          ensure_open!
          @subscriptions.add(channel)
          result
        end
      end

      def publish(channel:, data:) = request { |id| self.class.publish(id: id, channel: channel, data: data) }

      def unsubscribe(channel:)
        @subscription_lock.acquire do
          ensure_open!
          next {} unless @subscriptions.include?(channel)

          result = request { |id| self.class.unsubscribe(id: id, channel: channel) }
          @subscriptions.delete(channel)
          result
        end
      end

      def presence(channel:) = request { |id| self.class.presence(id: id, channel: channel) }

      def close
        return nil if @closed

        close_with(ClosedError.new('realtime connection closed'))
        @reader_task.stop && nil
      end

      private

      def load_async
        require 'async'
        require 'async/queue'
        require 'async/semaphore'
      end

      def configure_limits(limits)
        unknown = limits.keys - LIMIT_KEYS
        raise ArgumentError, "unknown keyword: #{unknown.first}" unless unknown.empty?

        @request_timeout = limits.fetch(:request_timeout, DEFAULT_REQUEST_TIMEOUT)
        @max_pending = limits.fetch(:max_pending, DEFAULT_MAX_PENDING)
        @max_callback_queue = limits.fetch(:max_callback_queue, DEFAULT_MAX_CALLBACK_QUEUE)
      end

      def ensure_open!
        raise @closed_error if @closed

        self
      end
    end
  end
end

require_relative 'protocol_io'
