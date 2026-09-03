# frozen_string_literal: true

module Volcano
  class Realtime
    # Reconnects unexpected transport losses and restores subscription intent.
    module Reconnect
      RECONNECT_MIN_DELAY = 0.1
      RECONNECT_MAX_DELAY = 20.0
      MAX_BACKOFF_EXPONENT = 8

      private

      def start_reconnect
        return if @closed || @reconnect_task || !reconnect_needed?

        @reconnect_task = Async::Task.current.async { reconnect_loop }
      end

      def stop_reconnect
        task = @reconnect_task
        @reconnect_task = nil
        task&.stop unless task.equal?(Async::Task.current)
      end

      def reconnect_loop
        attempt = 0
        loop do
          break if reconnect_attempt_finished?(attempt)

          attempt += 1
        end
      ensure
        @reconnect_task = nil if @reconnect_task.equal?(Async::Task.current)
      end

      def reconnect_attempt_finished?(attempt)
        wait_before_reconnect(attempt)
        return true unless reconnect_needed?

        protocol = current_or_connect_protocol
        return false unless protocol

        restore_subscriptions(protocol)
        subscriptions_restored?(protocol)
      end

      def wait_before_reconnect(attempt)
        delay = @reconnect_delay.call(attempt)
        Async::Task.current.sleep(delay) if delay.positive?
      end

      def current_or_connect_protocol
        protocol_lock.acquire do
          next @protocol if @protocol&.connected?

          connect_protocol
        end
      rescue StandardError
        nil
      end

      def restore_subscriptions(protocol)
        channels_snapshot.each do |channel|
          channel.restore_subscription(protocol)
        rescue StandardError => e
          report_channel_error(e)
        end
      end

      def subscriptions_restored?(protocol)
        return false unless @protocol.equal?(protocol) && protocol.connected?

        channels_snapshot.none?(&:restoration_needed?)
      end

      def channels_snapshot = channel_lock.acquire { @channels.values }

      def reconnect_needed? = !@closed && @channels.each_value.any?(&:restoration_needed?)

      def default_reconnect_delay(attempt)
        exponent = [attempt, MAX_BACKOFF_EXPONENT].min
        ceiling = [RECONNECT_MIN_DELAY * (2**exponent), RECONNECT_MAX_DELAY].min
        rand * ceiling
      end
    end
    private_constant :Reconnect
  end
end
