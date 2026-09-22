# frozen_string_literal: true

module VolcanoContract
  module LogAssertions
    def verify_events(events)
      verify_event_set(events)

      timestamps = events.map { |event| verify_event(event) }
      raise 'events are not newest first' unless timestamps == timestamps.sort.reverse!
    end

    def verify_activity(response)
      verify_bucket_totals(response)
      raise 'resource counts changed' unless dimension_total(response, 'resource_ids',
                                                             @fixture.fetch('function_id')) == 1
      raise 'level counts changed' unless dimension_total(response, 'levels', 'info') == 1
    end

    private

    def complete_event_ids(events)
      raise 'search did not find exactly three events' unless events.length == 3

      event_ids(events)
    end

    def verify_event_set(events)
      raise 'missing or duplicate event IDs' unless complete_event_ids(events).uniq.length == 3

      ordinals = events.map { |event| event.fetch('body').fetch('ordinal') }
      raise 'event ordinals changed' unless ordinals.sort == [0, 1, 2]
    end

    def verify_bucket_totals(response)
      raise 'activity total changed' unless response.total == 1 && response.data.length == 2

      totals = response.data.sum { |bucket| bucket.fetch('total') }
      raise 'bucket totals changed' unless totals == response.total
    end

    def event_ids(events)
      events.map { |event| event.fetch('id') }.sort!
    end

    def verify_event(event)
      body = event.fetch('body')
      raise 'event body changed' unless body == { 'marker' => @marker, 'ordinal' => body.fetch('ordinal') }
      raise 'event resource changed' unless event.fetch('resource').slice('type', 'id') ==
                                            { 'type' => 'function', 'id' => @fixture.fetch('function_id') }
      raise 'event metadata is missing' if event.fetch('id').empty? || event.fetch('level') != 'info'

      Time.iso8601(event.fetch('timestamp'))
    end

    def dimension_total(response, dimension, key)
      response.data.sum { |bucket| bucket.fetch('counts').fetch(dimension).fetch(key, 0) }
    end
  end
end
