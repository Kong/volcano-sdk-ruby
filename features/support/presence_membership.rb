# frozen_string_literal: true

require 'async/queue'

module VolcanoContract
  class PresenceObserver
    attr_reader :snapshots

    def initialize(channel, user_id)
      @channel = channel
      @user_id = user_id
      @snapshots = []
      @changed = Async::Queue.new
      channel.on_presence_sync do |state|
        @snapshots << state.keys.sort
        @changed.enqueue(true)
      end
    end

    def wait(task)
      task.with_timeout(10) do
        loop do
          return if yield

          @changed.dequeue
        end
      end
    end

    def roster(task, count)
      wait(task) { @channel.presence_state.length == count }
      state = @channel.presence_state
      state.each do |key, info|
        raise 'presence identity changed' unless info.user == @user_id && info.client == key && !key.empty?
      end
      state.keys.sort
    end
  end

  class PresenceMembership
    def initialize(world)
      @world = world
      @channels = world.realtime_clients.map do |client|
        client.realtime.channel(world.realtime_channel, type: :presence)
      end
    end

    def run(task)
      first, second = @channels
      observer = PresenceObserver.new(first, @world.fixture.fetch('user_id'))
      peer = PresenceObserver.new(second, @world.fixture.fetch('user_id'))
      check_membership(task, observer, peer)
    ensure
      @channels.each(&:unsubscribe)
    end

    private

    def check_membership(task, observer, peer)
      first, second = @channels
      first.subscribe
      initial = observer.roster(task, 1)
      second.subscribe
      joined = observer.roster(task, 2)
      raise 'presence rosters differ' unless peer.roster(task, 2) == joined && (initial - joined).empty?

      second.unsubscribe
      raise 'presence leave removed the wrong connection' unless observer.roster(task, 1) == initial

      observer.wait(task) { observed_membership?(observer.snapshots, [initial, joined, initial]) }
      [1, 2, 1]
    end

    def observed_membership?(snapshots, expected)
      index = 0
      snapshots.each do |state|
        index += 1 if state == expected[index]
        return true if index == expected.length
      end
      false
    end
  end
end
