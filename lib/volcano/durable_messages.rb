# frozen_string_literal: true

module Volcano
  # Messages an execution publishes, delivered to the block #subscribe took
  # until #unsubscribe.
  class DurableMessageSubscription
    def initialize(stream, channel, realtime)
      @stream = stream
      @channel = channel
      @realtime = realtime
    end

    # Stops delivering messages and leaves the execution's channel. Safe to
    # repeat, and to call from the block.
    def unsubscribe
      @stream.close
      @realtime.__send__(:remove_durable_channel, @channel)
    end
  end

  # Sends to, lists, and follows the messages of durable executions.
  #
  # Each method addresses an execution by its function's name or id and the
  # execution's id. By default they use the application route with the
  # client's credential, as Durable#start does; pass +client_token:+ where that
  # credential needs it, as an anon key or a user who did not start the
  # execution does. Pass +project_id:+ to use the owner's project route with
  # the session's platform token instead.
  class DurableMessages
    include DurableArguments
    include DurableMessageArguments
    include DurableMessageResponses

    Target = Data.define(:project_id, :function_id, :execution_id, :client_token)
    private_constant :Target

    SEND_OPTIONS = %i[idempotency_key client_token project_id].freeze
    LIST_OPTIONS = %i[direction name after limit client_token project_id].freeze
    private_constant :SEND_OPTIONS, :LIST_OPTIONS

    def initialize(client, transport, realtime)
      @client = client
      @transport = transport
      @realtime = realtime
    end

    # Sends a message to a running execution, queued until a wait for its
    # +name+ takes it. +data+ is any JSON value. Sending again with an
    # +idempotency_key:+ the execution has seen returns the message the first
    # send stored and sends nothing. Sending to an execution that has ended
    # raises Error::ConflictError, whose +code+ is +execution_not_running+.
    def send_message(function_name, execution_id, name, data = nil, **options)
      target = message_target(function_name, execution_id, known_options(options, SEND_OPTIONS))
      name = message_name(name)
      key = bounded_text(options[:idempotency_key], 'idempotency_key', MAX_IDEMPOTENCY_KEY_LENGTH)
      response = Transport.invoke do
        @transport.send_durable_message(
          authorization: authorization(target), target: target, name: name,
          data: ImmutableRequestValue.capture(data), idempotency_key: key
        )
      end
      durable_message(Transport.body(response, response.status == 200 ? 200 : 201))
    end

    # Lists an execution's messages in both directions, oldest first, filtered
    # by any of +direction+ (+in+ or +out+), +name+, +after+ (a +seq+), and
    # +limit+ (1 to 500), given as keywords with +client_token+ and
    # +project_id+. Read the next page with +after+ set to the last message's
    # +seq+.
    def list(function_name, execution_id, filters = {})
      filters = list_filters(filters)
      target = message_target(function_name, execution_id, filters)
      durable_message_page(Transport.body(list_messages(target, list_query(filters)), 200))
    end

    # Delivers every message the execution publishes to the block, in order
    # and once each. Messages it published before the call come first, and
    # after a reconnect the ones published meanwhile are read back before live
    # delivery resumes. Returns a DurableMessageSubscription once the messages
    # published so far are delivered; a block that raises meanwhile ends the
    # subscription and raises here.
    #
    # Follows the execution on the client's realtime connection, so call it
    # inside that connection's Async reactor, with a signed-in session. A
    # catch-up that fails after a reconnect is reported to Realtime#on_error.
    # Raises Realtime::DuplicateSubscriptionError when this client already
    # follows the execution.
    def subscribe(function_name, execution_id, client_token: nil, project_id: nil, &handler)
      raise ArgumentError, 'subscribe requires a block' unless handler

      target = message_target(function_name, execution_id, { client_token: client_token, project_id: project_id })
      stream = DurableMessageStream.new(handler, reader(target), failure_reporter)
      follow(stream, durable_channel(target, stream))
    end

    private

    def durable_channel(target, stream)
      @realtime.__send__(:durable_channel, target.execution_id, target.client_token, -> { stream.resubscribed }) ||
        raise(Realtime::DuplicateSubscriptionError, 'already subscribed to this execution; unsubscribe first')
    end

    def follow(stream, channel)
      subscription = DurableMessageSubscription.new(stream, channel, @realtime)
      channel.on('message') { |data| stream.live(data) }
      unsubscribe_unless_finished(subscription) do
        channel.subscribe
        stream.catch_up
      end
      subscription
    end

    # Also leaves the channel when the task running the block is stopped.
    def unsubscribe_unless_finished(subscription)
      finished = false
      begin
        yield
        finished = true
      ensure
        subscription.unsubscribe unless finished
      end
    end

    def reader(target)
      lambda do |after|
        durable_message_page(Transport.body(list_messages(target, { direction: 'out', after: after }), 200))
      end
    end

    def list_messages(target, query)
      Transport.invoke do
        @transport.list_durable_messages(authorization: authorization(target), target: target, query: query)
      end
    end

    def failure_reporter
      ->(error) { @realtime.__send__(:report_channel_error, error) }
    end

    def authorization(target)
      target.project_id ? @client.session_token : @client.function_token
    end

    def message_target(function_name, execution_id, options)
      project_id = options[:project_id]
      Target.new(
        project_id: project_id.nil? ? nil : identifier(project_id, 'project_id'),
        function_id: identifier(function_name, 'function_name'),
        execution_id: identifier(execution_id, 'execution_id'),
        client_token: bounded_text(options[:client_token], 'client_token', MAX_CLIENT_TOKEN_LENGTH)
      )
    end

    def list_filters(filters)
      raise TypeError, 'filters must be a Hash' unless filters.is_a?(Hash)

      known_options(filters, LIST_OPTIONS)
    end

    def list_query(filters)
      name = filters[:name]
      {
        direction: direction_filter(filters[:direction]), name: name.nil? ? nil : message_name(name),
        after: after_argument(filters[:after]), limit: limit_argument(filters[:limit])
      }.compact
    end

    def direction_filter(value)
      return if value.nil?

      DIRECTIONS.find { |direction| direction == value.to_s } || raise(ArgumentError, "direction must be 'in' or 'out'")
    end
  end
end
