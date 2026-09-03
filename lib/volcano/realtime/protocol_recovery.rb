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
          return unless position
          return if position_blocked_by_gap?(channel, position)

          @stream_positions[channel] = position
        end

        def drop_publication(channel, publication) = mark_publication_gap(channel, publication)

        private

        def initialize_recovery
          @stream_positions = {}
          @position_gaps = {}
        end

        def process_subscription_result(channel, result)
          return unless result.is_a?(Hash)

          publications = result.fetch('publications', [])
          return unless publications.is_a?(Array) && publications.all?(Hash)

          @position_gaps.delete(channel)
          remember_recovery_start(channel, result, publications)
          publications.each { |publication| dispatch_recovered_publication(channel, publication) }
          remember_subscription_position(channel, result) if publications.empty?
        end

        def remember_recovery_start(channel, result, publications)
          first_publication = publications.first
          return unless first_publication.is_a?(Hash)

          first_offset = first_publication['offset']
          return unless first_offset.is_a?(Integer) && first_offset.positive?

          position = immutable_position(result['epoch'], first_offset - 1)
          @stream_positions[channel] = position if position
        end

        def dispatch_recovered_publication(channel, publication)
          dispatch_publication(
            { 'channel' => channel, 'pub' => publication }, recovered: true, enforce_limit: false
          )
        end

        def remember_subscription_position(channel, result)
          position = immutable_position(result['epoch'], result['offset'])
          @stream_positions[channel] = position if position
        end

        def publication_position(publication, current)
          return unless publication.is_a?(Hash) && publication.key?('offset')

          immutable_position(publication.fetch('epoch', current.fetch(:epoch)), publication.fetch('offset'))
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
