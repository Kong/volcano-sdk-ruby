# frozen_string_literal: true

module Volcano
  # Captures immutable JSON for log requests and responses.
  module ImmutableLogJSON
    private

    def immutable_json(value)
      case value
      when Hash then immutable_json_hash(value)
      when Array then value.map { |item| immutable_json(item) }.freeze
      when Time, String then value.dup.freeze
      else value
      end
    end

    def immutable_json_hash(value)
      value.to_h { |key, item| [immutable_json(key), immutable_json(item)] }.freeze
    end
  end
  private_constant :ImmutableLogJSON

  LogSearchResponse = Data.define(:data, :limit, :has_more, :next_cursor)

  # Immutable page returned by a project log search.
  class LogSearchResponse
    include ImmutableLogJSON

    def initialize(data:, limit:, has_more:, next_cursor: nil)
      data = immutable_json(data)
      next_cursor = next_cursor&.dup&.freeze
      super
    end
  end

  LogActivityResponse = Data.define(:data, :total)

  # Immutable bucketed project log activity.
  class LogActivityResponse
    include ImmutableLogJSON

    def initialize(data:, total:)
      data = immutable_json(data)
      super
    end
  end
end
