# frozen_string_literal: true

module Volcano
  # Searches retained project logs and activity.
  class Logs
    include ImmutableLogJSON

    def initialize(client, transport)
      @client = client
      @transport = transport
    end

    def search(project_id, request)
      project_id, request = log_request(project_id, request)
      response = @client.session_request do |token|
        Transport.invoke do
          @transport.search_project_logs(
            authorization: token,
            project_id: project_id,
            request: request
          )
        end
      end
      search_response(Transport.body(response, 200))
    end

    def activity(project_id, request)
      project_id, request = log_request(project_id, request)
      response = @client.session_request do |token|
        Transport.invoke do
          @transport.get_project_log_activity(
            authorization: token,
            project_id: project_id,
            request: request
          )
        end
      end
      activity_response(Transport.body(response, 200))
    end

    private

    def log_request(project_id, request)
      unless project_id.is_a?(String) && !project_id.strip.empty?
        raise ArgumentError, 'project_id must be a non-empty String'
      end
      raise TypeError, 'Log request must be a Hash' unless request.is_a?(Hash)

      [project_id.dup.freeze, immutable_json(request)]
    end

    def search_response(body)
      data = response_data(body)
      limit = body['limit']
      has_more = body['has_more']
      next_cursor = body['next_cursor']
      unless limit.is_a?(Integer) && [true, false].include?(has_more) &&
             (next_cursor.nil? || next_cursor.is_a?(String))
        raise TypeError, 'Expected a complete log response'
      end

      LogSearchResponse.new(
        data: data, limit: limit, has_more: has_more, next_cursor: next_cursor
      )
    end

    def activity_response(body)
      data = response_data(body)
      total = body['total']
      raise TypeError, 'Expected a complete log response' unless total.is_a?(Integer)

      LogActivityResponse.new(data: data, total: total)
    end

    def response_data(body)
      data = body['data'] if body.is_a?(Hash)
      raise TypeError, 'Expected a complete log response' unless data.is_a?(Array) && data.all?(Hash)

      data
    end
  end
end
