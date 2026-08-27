# frozen_string_literal: true

module Volcano
  class Realtime
    # Centrifuge protocol implementation extended with socket IO helpers.
    class Protocol
      # Coordinates protocol requests and the socket reader loop.
      module IO
        private

        def request
          ensure_open!
          id, reply_queue = register_request
          write_frame(yield(id))
          reply = await_reply(reply_queue)
          raise reply.error if reply.is_a?(Failure)

          reply
        rescue StandardError => e
          raise Redaction.exception(e, secrets: @secrets), cause: nil
        ensure
          @pending.delete(id) if defined?(id)
        end

        def register_request
          if @pending.length >= @max_pending
            raise PendingLimitError, "realtime pending command limit #{@max_pending} reached"
          end

          @next_id += 1
          [@next_id, Async::Queue.new].tap { |id, queue| @pending[id] = queue }
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
          close_with(ClosedError.new(invalid_frame_message(e)))
        rescue StandardError => e
          close_with(closed_error(e))
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
            closed.set_backtrace(error.backtrace)
          end
        end
      end

      include IO

      private_constant :IO
    end
  end
end
