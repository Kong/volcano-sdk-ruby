# frozen_string_literal: true

module Volcano
  class Realtime
    # Validates recovery subscribe results before updating stream positions.
    module ProtocolRecovery
      private

      def subscribe_request(channel:, recoverable:, join_leave:, recovery:)
        on_reply = nil
        if recovery
          on_reply = lambda do |reply|
            parse_recovery_result(channel: channel, recovery: recovery, result: reply)
          end
        end

        request(on_reply:) do |id|
          self.class.subscribe(
            id: id,
            channel: channel,
            recoverable: recoverable,
            join_leave: join_leave,
            recovery: recovery
          )
        end
      end

      def parse_recovery_result(channel:, recovery:, result:)
        result_position, publications = validated_recovery_result(result)
        return block_malformed_recovery_result(channel, recovery) unless result_position

        requested_position = requested_recovery_position(recovery)
        return block_recovery_result(channel, requested_position) if unrecovered_empty_result?(
          result, requested_position, publications
        )
        return install_empty_recovery_result(channel, result_position) if publications.empty?

        install_retained_recovery_result(channel, requested_position, publications)
      end

      def block_malformed_recovery_result(channel, recovery)
        block_recovery_result(channel, requested_recovery_position(recovery))
      end

      def block_recovery_result(channel, requested_position)
        replace_recovery_position(channel, requested_position) if requested_position
        mark_unknown_gap(channel)
        []
      end

      def unrecovered_empty_result?(result, requested_position, publications)
        requested_position && result['recovered'] == false && publications.empty?
      end

      def validated_recovery_result(result)
        return [nil, nil] unless result.is_a?(Hash)

        result_position = recovery_position(result['epoch'], result['offset'])
        return [nil, nil] unless result_position

        publications = result.fetch('publications', [])
        return [nil, nil] unless publications.is_a?(Array)

        validated = publications.map { |publication| validated_recovery_publication(publication, result_position) }
        return [nil, nil] if validated.any?(&:nil?)

        [result_position, validated]
      end

      def validated_recovery_publication(publication, fallback_position)
        return unless publication.is_a?(Hash)

        position = recovery_position(publication.fetch('epoch', fallback_position.fetch(:epoch)), publication['offset'])
        return unless position

        [publication, position]
      end

      def requested_recovery_position(recovery)
        return unless recovery.is_a?(Hash)

        recovery_position(recovery[:epoch], recovery[:offset])
      end

      def install_empty_recovery_result(channel, result_position)
        replace_recovery_position(channel, result_position)
        []
      end

      def install_retained_recovery_result(channel, requested_position, publications)
        first_publication, first_position = publications.fetch(0)
        position = requested_position || recovery_position(
          first_position.fetch(:epoch), first_position.fetch(:offset) - 1
        )
        return [] unless position

        replace_recovery_position(channel, position)
        mark_retained_gap(channel, position, first_position, first_publication) if requested_position
        publications.map(&:first)
      end

      def replace_recovery_position(channel, position)
        delete_recovery_state(channel)
        set_recovery_position(channel, position.fetch(:epoch), position.fetch(:offset))
      end

      def mark_retained_gap(channel, current, first_position, first_publication)
        if same_epoch?(current, first_position) && first_position.fetch(:offset) > current.fetch(:offset) + 1
          mark_publication_gap(channel, { 'epoch' => current.fetch(:epoch), 'offset' => current.fetch(:offset) + 1 })
        elsif !same_epoch?(current, first_position)
          mark_publication_gap(channel, first_publication)
        end
      end
    end
  end
end
