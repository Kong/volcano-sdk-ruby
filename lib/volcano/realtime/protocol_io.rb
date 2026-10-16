# frozen_string_literal: true

module Volcano
  class Realtime
    # Centrifuge protocol implementation extended with socket IO helpers.
    class Protocol
      # Coordinates protocol requests and the socket reader loop.
      module IO
        # @dynamic ensure_open!, close_with, process

        private

        # on_write runs once the frame holds the write lock, when the server may
        # start to receive it.
        def request(reply_key, on_reply: nil, on_write: nil)
          # @type var registered_id: Integer?
          ensure_open!
          registered_id, reply_queue = register_request(reply_key, on_reply)
          write_frame(yield(registered_id || raise(TypeError, 'invalid realtime request id')), on_write)
          reply = await_reply(reply_queue)
          raise reply.error if reply.is_a?(Failure)

          reply
        rescue StandardError => e
          raise Redaction.exception(e, secrets: @secrets), cause: nil
        ensure
          @pending.delete(registered_id) if registered_id
        end

        def register_request(reply_key, on_reply)
          if @pending.length >= @max_pending
            raise PendingLimitError, "realtime pending command limit #{@max_pending} reached"
          end

          @next_id += 1
          queue = Async::Queue.new
          @pending[@next_id] = Pending.new(queue: queue, on_reply: on_reply, reply_key: reply_key)
          [@next_id, queue]
        end

        def write_frame(frame, on_write = nil) = write_serialized_frame("#{JSON.generate(frame)}\n", on_write)

        def write_serialized_frame(frame, on_write = nil)
          @write_lock.acquire do
            on_write&.call
            @socket.write(frame)
            @socket.flush
          end
        rescue StandardError => e
          failure = closed_error(e)
          close_with(failure, notify_error: true)
          raise failure
        end

        def await_reply(reply_queue)
          Async::Task.current.with_timeout(
            @request_timeout,
            RequestTimeoutError,
            "realtime command timed out after #{@request_timeout} seconds"
          ) { reply_queue.dequeue }
        end

        def read_loop
          while (message = read_message)
            process_message(message)
          end
        rescue JSON::ParserError => e
          close_with(ClosedError.new(invalid_frame_message(e)), notify_error: true)
        rescue StandardError => e
          close_with(closed_error(e), notify_error: true)
        ensure
          close_with(ClosedError.new('realtime connection closed'))
        end

        def read_message
          Async::Task.current.yield
          @socket.read
        end

        def process_message(message)
          message.to_str.each_line do |line|
            process(JSON.parse(line)) unless line.strip.empty?
          end
        end

        def invalid_frame_message(error)
          Redaction.message("invalid realtime frame: #{error.message}", secrets: @secrets)
        end

        def closed_error(error)
          ClosedError.new(Redaction.message(error.message, secrets: @secrets)).tap do |closed|
            trace = error.backtrace
            closed.set_backtrace(trace) if trace
          end
        end
      end

      include IO

      private_constant :IO
    end
  end
end
