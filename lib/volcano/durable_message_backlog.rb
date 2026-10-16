# frozen_string_literal: true

module Volcano
  # The live messages a durable message stream holds until the ones before
  # them are delivered. Past LIMIT the oldest is dropped. Each one held after a
  # dropped one names a predecessor at or past it, so it waits for a read that
  # lists the dropped one.
  class DurableMessageBacklog
    LIMIT = 128
    private_constant :LIMIT

    def initialize
      @held = []
    end

    def empty? = @held.empty?

    def clear = @held.clear

    def hold(held)
      @held << held
      @held.delete(oldest) if @held.size > LIMIT
      nil
    end

    # Takes the oldest held message if the one its broadcast names as the one
    # before it is delivered.
    def take_following(last_seq)
      held = oldest
      @held.delete(held) if held && held.prev_seq <= last_seq
    end

    private

    def oldest = @held.min_by { |candidate| candidate.message.seq }
  end
  private_constant :DurableMessageBacklog
end
