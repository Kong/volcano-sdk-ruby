# frozen_string_literal: true

require 'English'

module Volcano
  # Keeps refresh and revocation attached to one explicit sign-in/adoption.
  class SessionOperations
    Outcome = Struct.new(:done, :value, :error)
    private_constant :Outcome

    def initialize(verified = nil)
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @refresh = nil
      @sign_out = nil
      verify_pair(verified)
    end

    def verify_pair(session)
      @mutex.synchronize { @verified_pair = session && [session.access_token, session.refresh_token].freeze }
    end

    def verified_pair?(session)
      @mutex.synchronize { session.refresh_token && @verified_pair == [session.access_token, session.refresh_token] }
    end

    def closing? = @mutex.synchronize { !@sign_out.nil? }

    def refresh(&)
      operation, owner = @mutex.synchronize do
        raise Error::SessionChangedError if @sign_out
        next [@refresh, false] if @refresh && !@refresh.done

        @refresh = Outcome.new(false)
        [@refresh, true]
      end
      execute(operation, owner, &)
    end

    def sign_out
      operation, owner, preceding, pending = @mutex.synchronize do
        first = @sign_out.nil?
        @sign_out ||= Outcome.new(false)
        [@sign_out, first, @refresh, @refresh && !@refresh.done]
      end
      execute(operation, owner) { yield(preceding, pending) }
    end

    def result(operation)
      return unless operation

      @mutex.synchronize { @condition.wait(@mutex) until operation.done }
      raise operation.error if operation.error

      operation.value
    end

    private

    def execute(operation, owner)
      return result(operation) unless owner

      completed = false
      begin
        value = yield
        completed = true
      ensure
        complete(operation, value, completed ? nil : $ERROR_INFO)
      end
      value
    end

    def complete(operation, value, error)
      @mutex.synchronize do
        operation.value = value
        operation.error = error
        operation.done = true
        @condition.broadcast
      end
    end
  end
end
