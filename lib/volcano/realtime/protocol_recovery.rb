# frozen_string_literal: true

module Volcano
  class Realtime
    class Protocol
      # Tracks recoverable stream positions for active subscriptions.
      module ProtocolRecovery
        def position(channel) = @stream_positions[channel]

        def complete_publication(channel, publication)
          remember_publication_position(channel, publication)
        end

        def drop_publication(channel, publication)
          mark_publication_gap(channel, publication)
        end

        private

        def initialize_recovery
          @stream_positions = {}
          @position_gaps = {}
        end

        def process_subscription_result(channel, result)
          @position_gaps.delete(channel)
          publications = result.fetch('publications', [])
          remember_recovery_start(channel, result, publications)
          publications.each { |publication| dispatch_recovered_publication(channel, publication) }
          remember_subscription_position(channel, result) if publications.empty?
        end

        def remember_recovery_start(channel, result, publications)
          return if publications.empty?

          epoch = result['epoch']
          current = @stream_positions[channel]
          return if current && current.fetch(:epoch) == epoch

          offset = publications.first['offset']
          position = immutable_position(epoch, [offset - 1, 0].max) if offset.is_a?(Integer)
          @stream_positions[channel] = position if position
        end

        def dispatch_recovered_publication(channel, publication)
          dispatch_publication(
            { 'channel' => channel, 'pub' => publication },
            enforce_limit: false,
            registered_channel: channel,
            recovered: true
          )
        end

        def remember_subscription_position(channel, result)
          return unless result['recoverable']

          position = result_position(result)
          @stream_positions[channel] = position if position
        end

        def remember_requested_position(channel, recovery)
          return unless recovery&.key?(:epoch) && recovery.key?(:offset)

          position = immutable_position(recovery.fetch(:epoch), recovery.fetch(:offset))
          @stream_positions[channel] = position if position
        end

        def remember_publication_position(channel, publication)
          current = @stream_positions[channel]
          return unless current

          position = publication_position(publication, current)
          return unless position
          return current if position_blocked?(channel, position)

          @stream_positions[channel] = position
        end

        def mark_publication_gap(channel, publication)
          current = @stream_positions[channel]
          return unless current

          gap = publication_position(publication, current)
          return @position_gaps[channel] = true unless gap

          existing = @position_gaps[channel]
          @position_gaps[channel] = gap if !existing || earlier_position?(gap, existing)
        end

        def position_blocked?(channel, position)
          gap = @position_gaps[channel]
          return false unless gap
          return true unless gap.is_a?(Hash) && gap.fetch(:epoch) == position.fetch(:epoch)

          position.fetch(:offset) >= gap.fetch(:offset)
        end

        def earlier_position?(candidate, existing)
          return false unless existing.is_a?(Hash)
          return false unless candidate.fetch(:epoch) == existing.fetch(:epoch)

          candidate.fetch(:offset) < existing.fetch(:offset)
        end

        def result_position(result)
          immutable_position(result.fetch('epoch', ''), result.fetch('offset', 0))
        end

        def publication_position(publication, current)
          return unless publication.key?('offset')

          immutable_position(
            publication.fetch('epoch', current.fetch(:epoch)),
            publication.fetch('offset')
          )
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
