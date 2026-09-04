# frozen_string_literal: true

module Volcano
  class Realtime
    # Tracks recoverable Centrifuge stream positions independently of subscriptions.
    module ProtocolRecoveryPosition
      private

      def initialize_recovery_positions
        @stream_positions = {}
        @position_gaps = {}
      end

      def position(channel) = @stream_positions[channel]

      def set_recovery_position(channel, epoch, offset)
        position = recovery_position(epoch, offset)
        return unless position

        @stream_positions[channel] = position
      end

      def complete_publication(channel, publication)
        current = @stream_positions[channel]
        return unless current

        completed = publication_position(publication, current)
        return mark_unknown_gap(channel) unless same_epoch?(completed, current)
        return if stale_position?(completed, current)
        return mark_unknown_gap(channel) unless next_position?(completed, current)
        return unless completion_before_gap?(channel, completed)

        @stream_positions[channel] = completed
      end

      def drop_publication(channel, publication)
        mark_publication_gap(channel, publication)
      end

      def delete_recovery_state(channel)
        @stream_positions.delete(channel)
        @position_gaps.delete(channel)
      end

      def mark_publication_gap(channel, publication)
        current = @stream_positions[channel]
        return unless current

        gap = publication_position(publication, current)
        return @position_gaps[channel] = true unless same_epoch?(gap, current)
        return if gap.fetch(:offset) <= current.fetch(:offset)

        existing = @position_gaps[channel]
        return if existing == true
        return if existing && existing.fetch(:offset) <= gap.fetch(:offset)

        @position_gaps[channel] = gap
      end

      def publication_position(publication, fallback)
        return fallback unless publication.is_a?(Hash)

        recovery_position(publication['epoch'], publication['offset']) || fallback
      end

      def recovery_position(epoch, offset)
        return unless epoch.is_a?(String) && !epoch.empty?
        return unless offset.is_a?(Integer) && offset >= 0

        { epoch: epoch.dup.freeze, offset: offset.freeze }.freeze
      end

      def same_epoch?(first, second) = first.fetch(:epoch) == second.fetch(:epoch)

      def stale_position?(position, current) = position.fetch(:offset) <= current.fetch(:offset)

      def next_position?(position, current) = position.fetch(:offset) == current.fetch(:offset) + 1

      def completion_before_gap?(channel, completed)
        gap = @position_gaps[channel]
        gap != true && (!gap || completed.fetch(:offset) < gap.fetch(:offset))
      end

      def mark_unknown_gap(channel) = @position_gaps[channel] = true
    end
  end
end
