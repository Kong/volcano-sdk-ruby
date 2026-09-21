# frozen_string_literal: true

module Volcano
  # Immutable result of one function invocation.
  FunctionResponse = Data.define(:data, :status, :headers, :version) do
    def initialize(data:, status:, headers:, version:)
      super(
        data: immutable_json(data),
        status: status,
        headers: immutable_json(headers),
        version: version&.dup&.freeze
      )
    end

    private

    def immutable_json(value)
      case value
      when Hash then immutable_json_hash(value)
      when Array then value.map { |item| immutable_json(item) }.freeze
      when String then value.dup.freeze
      else value
      end
    end

    def immutable_json_hash(value)
      value.to_h { |key, item| [immutable_json(key), immutable_json(item)] }.freeze
    end
  end
end
