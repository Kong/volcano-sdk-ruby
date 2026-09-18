# frozen_string_literal: true

require 'async/queue'
require 'securerandom'
require 'time'

module VolcanoContract
  class ChangeObserver
    attr_reader :events, :inserts, :wrong_table

    def initialize(channel, table)
      @events = []
      @inserts = []
      @wrong_table = []
      @queue = Async::Queue.new
      channel.on_postgres_changes('*', schema: 'public', table: table) do |event|
        @events << event
        @queue.enqueue(event)
      end
      channel.on_postgres_changes('INSERT', schema: 'public', table: table) { |event| @inserts << event }
      channel.on_postgres_changes('*', schema: 'public', table: "#{table}_other") { |event| @wrong_table << event }
    end

    def next(task)
      task.with_timeout(10) { @queue.dequeue }
    end

    def verify_filters
      raise 'Postgres event order changed' unless events.map(&:type) == %w[INSERT UPDATE]
      raise 'Postgres event filters changed' unless inserts.length == 1 && wrong_table.empty?
    end
  end

  class PostgresChanges
    def initialize(world)
      @world = world
      @table_name = world.fixture.fetch('realtime_table_name')
      initialize_row(world)
      @channels = build_channels(world)
    end

    def run(task)
      observers = @channels.map { |channel| ChangeObserver.new(channel, @table_name) }
      @channels.each(&:subscribe)
      %w[INSERT UPDATE].each_with_index { |kind, index| change_and_receive(task, observers, kind, index) }
      observers.each(&:verify_filters)
      %w[INSERT UPDATE]
    ensure
      @channels.each(&:unsubscribe)
    end

    private

    def initialize_row(world)
      @row = { 'id' => SecureRandom.uuid, 'value' => 'inserted', 'owner_id' => world.fixture.fetch('user_id') }
      @table = world.client.database(world.fixture.fetch('database_name')).from(@table_name)
      world.register_cleanup(-> { @table.delete.eq('id', @row.fetch('id')).execute })
    end

    def build_channels(world)
      world.realtime_clients.each_with_index.map do |client, index|
        client.realtime.database_name = world.fixture.fetch('database_name')
        client.realtime.channel("public:#{@table_name}", type: :postgres, auto_fetch: index.zero?)
      end
    end

    def change_and_receive(task, observers, kind, index)
      expected = @row.merge('value' => index.zero? ? 'inserted' : 'updated')
      operation = if index.zero?
                    @table.insert(expected)
                  else
                    @table.update('value' => expected.fetch('value')).eq('id', @row.fetch('id'))
                  end
      raise 'Postgres mutation result changed' unless operation.execute == [expected]

      observers.each_with_index do |observer, client_index|
        verify_change(observer.next(task), kind, expected, automatic: client_index.zero?)
      end
    end

    def verify_change(event, kind, expected, automatic:)
      unless [event.type, event.schema, event.table] == [kind, 'public', @table_name]
        raise 'Postgres notification metadata changed'
      end

      Time.iso8601(event.timestamp)
      verify_body(event, expected, automatic: automatic)
    end

    def verify_body(event, expected, automatic:)
      if automatic
        raise 'automatic row lookup did not retain values' unless event.record == expected
      elsif event.id != expected.fetch('id') || event.mode != 'lightweight' || !event.record.nil?
        raise 'lightweight notification changed'
      end
    end
  end
end
