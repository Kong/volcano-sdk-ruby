# frozen_string_literal: true

module SpecSupport
  module GeneratedAPI
    class FakeDatabaseApi
      attr_reader :calls, :delete_calls, :insert_calls, :update_calls

      def initialize
        @calls = []
        @insert_calls = []
        @update_calls = []
        @delete_calls = []
      end

      def query_database_select_with_http_info(name, body)
        @calls << [name, body]
        [FakeGeneratedModel.new(data: [{ slug: 'a' }]), 200, {}]
      end

      def query_database_insert_with_http_info(name, body)
        @insert_calls << [name, body]
        [FakeGeneratedModel.new(data: [{ slug: 'new' }]), 200, {}]
      end

      def query_database_update_with_http_info(name, body)
        @update_calls << [name, body]
        [FakeGeneratedModel.new(data: [{ slug: 'updated' }]), 200, {}]
      end

      def query_database_delete_with_http_info(name, body)
        @delete_calls << [name, body]
        [FakeGeneratedModel.new(data: [{ slug: 'deleted' }]), 200, {}]
      end
    end
  end
end
