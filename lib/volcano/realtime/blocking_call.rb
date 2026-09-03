# frozen_string_literal: true

module Volcano
  class Realtime
    # Runs one blocking operation off the Async reactor and returns its result.
    module BlockingCall
      Result = Data.define(:value, :error)
      private_constant :Result

      module_function

      def call(&operation)
        results = ::Queue.new
        worker = Thread.new { execute(results, operation) }
        worker.report_on_exception = false
        result = results.pop
        worker.join
        raise result.error if result.error

        result.value
      end

      def execute(results, operation)
        results << Result.new(value: operation.call, error: nil)
      rescue StandardError => e
        results << Result.new(value: nil, error: e)
      end
      private_class_method :execute
    end
    private_constant :BlockingCall
  end
end
