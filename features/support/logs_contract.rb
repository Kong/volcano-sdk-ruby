# frozen_string_literal: true

require 'time'
require_relative 'log_assertions'

module VolcanoContract
  class Logs
    include LogAssertions

    def initialize(world)
      @world = world
      @fixture = world.fixture
      @client = Volcano::Client.new(
        api_url: @fixture.fetch('api_url'), anon_key: @fixture.fetch('anon_key'),
        access_token: @fixture.fetch('logs_access_token'), timeout: 10
      )
      @marker = "sdklogs#{SecureRandom.hex(16)}"
      @request = {
        resource: { type: 'function', ids: [@fixture.fetch('function_id')] },
        q: @marker, start_time: (Time.now.utc - 5).iso8601(6)
      }
    end

    def emit(count)
      count.times do |ordinal|
        response = @world.service_client.functions.invoke(
          @fixture.fetch('function_name'),
          { value: 'contract', log_marker: @marker, log_ordinal: ordinal }
        )
        raise 'function invocation did not echo the payload' unless response.status == 200 &&
                                                                    response.data == { 'echoed' => 'contract' }
      end
      @request[:end_time] = (Time.now.utc + 1).iso8601(6)
    end

    def search
      page = poll(240, ->(response) { response.data.length >= 3 }) do
        @client.logs.search(@fixture.fetch('project_id'), @request.merge(limit: 100))
      end
      expected_ids = complete_event_ids(page.data)
      events = paginate
      raise 'pagination changed the event set' unless event_ids(events) == expected_ids

      events
    end

    def activity
      poll(120, ->(response) { response.total >= 1 }) do
        @client.logs.activity(@fixture.fetch('project_id'), @request.merge(bucket_count: 2))
      end
    end

    private

    def search_page(request)
      page = @client.logs.search(@fixture.fetch('project_id'), request)
      raise 'page limit changed' unless page.limit == 1 && page.data.length == 1

      page
    end

    def next_request(request, page)
      raise 'continuation cursor is missing' if page.next_cursor.to_s.empty?

      request.merge(cursor: page.next_cursor)
    end

    def paginate
      request = @request.merge(limit: 1)
      events = []
      3.times do
        page = search_page(request)

        events.concat(page.data)
        return events unless page.has_more

        request = next_request(request, page)
      end
      raise 'pagination did not terminate'
    end

    def poll(seconds, ready)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      loop do
        response = yield
        return response if ready.call(response)

        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise 'matching logs did not arrive before deadline' unless remaining.positive?

        sleep [1, remaining].min
      end
    end
  end
end
