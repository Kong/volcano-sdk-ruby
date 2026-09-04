# frozen_string_literal: true

module Volcano
  class Realtime
    class Protocol
      # Tracks recoverable stream positions for active subscriptions.
      module ProtocolRecovery
        def position(channel) = @stream_positions[channel]

        def complete_publication(channel, publication)
          current = @stream_positions[channel]
          return unless current

          position = publication_position(publication, current)
          return if invalid_publication_position?(channel, publication, current, position)
          return if non_successor_publication_position?(channel, current, position)
          return if position_blocked_by_gap?(channel, position)

          @stream_positions[channel] = position
        end

        def drop_publication(channel, publication) = mark_publication_gap(channel, publication)

        def delete_recovery_state(channel)
          @stream_positions.delete(channel)
          @position_gaps.delete(channel)
          nil
        end

        private

        def initialize_recovery
          @stream_positions = {}
          @position_gaps = {}
        end

        def recovery_result_handler(channel, recovery)
          return if recovery.nil?

          requested_position = immutable_position(recovery[:epoch], recovery[:offset])
          ->(reply) { process_subscription_result(channel, reply, requested_position) }
        end

        def process_subscription_result(channel, result, requested_position)
          @stream_positions[channel] = requested_position if requested_position
          return mark_invalid_subscription_baseline(channel) unless result.is_a?(Hash)

          publications = result.fetch('publications', [])
          return mark_invalid_subscription_baseline(channel) unless publications.is_a?(Array)

          replace_subscription_position(channel, result, publications, requested_position)
          enqueue_recovered_publications(channel, publications)
        end

        def replace_subscription_position(channel, result, publications, requested_position)
          position = subscription_position(result, publications, requested_position)
          unless position
            mark_invalid_subscription_baseline(channel)
            return
          end

          @stream_positions[channel] = position
          @position_gaps.delete(channel)
          mark_skipped_offset_gap(channel, requested_position) if recovery_gap?(requested_position, publications)
        end

        def mark_invalid_subscription_baseline(channel)
          @position_gaps[channel] = true if @stream_positions.key?(channel)
          nil
        end

        def subscription_position(result, publications, requested_position)
          return immutable_position(result['epoch'], result['offset']) if publications.empty?

          first_offset = publications.first['offset'] if publications.first.is_a?(Hash)
          return unless first_offset.is_a?(Integer) && first_offset.positive?

          return immutable_position(result['epoch'], first_offset - 1) unless requested_position

          requested_position if result['epoch'] == requested_position.fetch(:epoch)
        end

        def recovery_gap?(position, pubs) = position && pubs.first && pubs.first['offset'] != position[:offset] + 1

        def publication_position(publication, current)
          return unless publication.is_a?(Hash) && publication.key?('offset')

          immutable_position(publication.fetch('epoch', current.fetch(:epoch)), publication.fetch('offset'))
        end

        def invalid_publication_position?(channel, publication, current, position)
          return false if position && position.fetch(:epoch) == current.fetch(:epoch)

          mark_publication_gap(channel, publication)
          true
        end

        def non_successor_publication_position?(channel, current, position)
          expected_offset = current.fetch(:offset) + 1
          return false if position.fetch(:offset) == expected_offset

          mark_skipped_offset_gap(channel, current) if position.fetch(:offset) > expected_offset
          true
        end

        def mark_skipped_offset_gap(channel, current)
          mark_publication_gap(
            channel,
            'epoch' => current.fetch(:epoch), 'offset' => current.fetch(:offset) + 1
          )
        end

        def mark_publication_gap(channel, publication)
          current = @stream_positions[channel]
          return unless current

          gap = publication_position(publication, current)
          return @position_gaps[channel] = true unless gap_for_current_epoch?(gap, current)

          existing_gap = @position_gaps[channel]
          return if existing_gap == true
          return if existing_gap && existing_gap.fetch(:offset) <= gap.fetch(:offset)

          @position_gaps[channel] = gap
        end

        def gap_for_current_epoch?(gap, current)
          gap && gap.fetch(:epoch) == current.fetch(:epoch)
        end

        def position_blocked_by_gap?(channel, position)
          gap = @position_gaps[channel]
          return true if gap == true
          return false unless gap

          gap.fetch(:epoch) == position.fetch(:epoch) && position.fetch(:offset) >= gap.fetch(:offset)
        end

        def immutable_position(epoch, offset)
          return unless epoch.is_a?(String) && offset.is_a?(Integer) && !offset.negative?

          { epoch: epoch.dup.freeze, offset: offset }.freeze
        end
      end
      private_constant :ProtocolRecovery
    end
  end
end
