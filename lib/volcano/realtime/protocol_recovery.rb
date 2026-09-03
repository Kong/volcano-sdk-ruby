# frozen_string_literal: true

module Volcano
  class Realtime
    class Protocol
      # Tracks recoverable stream positions for active subscriptions.
      module ProtocolRecovery
        def position(channel) = @stream_positions[channel]

        private

        def initialize_recovery = @stream_positions = {}

        def process_subscription_result(channel, result)
          publications = result.fetch('publications', [])
          publications.each { |publication| dispatch_recovered_publication(channel, publication) }
          remember_subscription_position(channel, result) if publications.empty?
        end

        def dispatch_recovered_publication(channel, publication)
          dispatch_publication(
            { 'channel' => channel, 'pub' => publication },
            enforce_limit: false
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
          @stream_positions[channel] = position if position
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
