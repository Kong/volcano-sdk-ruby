# frozen_string_literal: true

require 'async/queue'

module VolcanoContract
  class BroadcastPause
    def initialize(world)
      @world = world
      @received = Async::Queue.new
      @delivered = []
    end

    def run(task)
      @world.subscriber.on('message') { |message| record(message) }
      @world.subscriber.subscribe
      @world.publisher.subscribe
      publish_and_receive(task, message('baseline'))
      pause(task)
      @world.subscriber.subscribe
      publish_and_receive(task, @world.realtime_message)
    end

    private

    def record(message)
      @delivered << message
      @received.enqueue(message)
    end

    def message(suffix)
      @world.realtime_message.merge('value' => "#{@world.realtime_message.fetch('value')}-#{suffix}")
    end

    def pause(task)
      @world.subscriber.unsubscribe
      @delivered.clear
      @world.publisher.send(**message('paused').transform_keys(&:to_sym))
      task.sleep(1)
      raise 'subscriber delivered a message while paused' unless @delivered.empty?
    end

    def publish_and_receive(task, message)
      task.with_timeout(10) do
        @world.publisher.send(**message.transform_keys(&:to_sym))
        loop do
          delivered = @received.dequeue
          return delivered if delivered == message
        end
      end
    end
  end
end
