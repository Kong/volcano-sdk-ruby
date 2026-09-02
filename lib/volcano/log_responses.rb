# frozen_string_literal: true

module Volcano
  # Deeply freezes JSON values owned by public log responses.
  module ImmutableLogJSON
    private

    def immutable_json(value)
      case value
      when Hash then value.to_h { |key, item| [immutable_json(key), immutable_json(item)] }.freeze
      when Array then value.map { |item| immutable_json(item) }.freeze
      when String then value.dup.freeze
      else value
      end
    end
  end
  private_constant :ImmutableLogJSON

  # Immutable page returned by a project log search.
  LogSearchResponse = Data.define(:data, :limit, :has_more, :next_cursor) do
    include ImmutableLogJSON

    def initialize(data:, limit:, has_more:, next_cursor: nil)
      super(
        data: immutable_json(data), limit: limit, has_more: has_more,
        next_cursor: next_cursor&.dup&.freeze
      )
    end
  end

  # Immutable bucketed project log activity.
  LogActivityResponse = Data.define(:data, :total) do
    include ImmutableLogJSON

    def initialize(data:, total:)
      super(data: immutable_json(data), total: total)
    end
  end
end
