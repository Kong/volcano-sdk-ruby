# frozen_string_literal: true

module Volcano
  class Realtime
    # Runs one blocking operation off the Async reactor and returns its result.
    module BlockingCall
      Success = Data.define(:value)
      Failure = Data.define(:error)
      private_constant :Success, :Failure

      def self.call(&operation)
        results = ::Queue.new
        worker = Thread.new { execute(results, operation) }
        worker.report_on_exception = false
        result = results.pop
        worker.join
        raise result.error if result.is_a?(Failure)

        result.value
      end

      def self.execute(results, operation)
        results << Success.new(value: operation.call)
      rescue StandardError => e
        results << Failure.new(error: e)
      end
      private_class_method :execute
    end
    private_constant :BlockingCall
  end
end
