# frozen_string_literal: true

require 'spec_helper'
require 'socket'

RSpec.describe 'Volcano SDK errors' do
  ErrorResponse = Data.define(:status, :body, :headers, :data) unless const_defined?(:ErrorResponse)

  class ErrorTransport
    def initialize(failure)
      @failure = failure
    end

    def auth_signin(**)
      raise @failure if @failure.is_a?(Exception)

      @failure
    end
  end

  {
    400 => 'Volcano::Error::ValidationError',
    422 => 'Volcano::Error::ValidationError',
    401 => 'Volcano::Error::AuthenticationError',
    403 => 'Volcano::Error::AuthenticationError',
    404 => 'Volcano::Error::NotFoundError',
    409 => 'Volcano::Error::ConflictError',
    429 => 'Volcano::Error::RateLimitedError',
    500 => 'Volcano::Error::ServerError',
    503 => 'Volcano::Error::ServerError'
  }.each do |status, error_name|
    it "maps HTTP #{status} to #{error_name}", :aggregate_failures do
      response = ErrorResponse.new(
        status: status,
        body: { 'error' => 'contract failure', 'code' => 'contract_code' },
        headers: { 'Retry-After' => '17' },
        data: nil
      )
      client = Volcano::Client.new(anon_key: 'anon-key', _transport: ErrorTransport.new(response))

      expect do
        client.auth.sign_in(email: 'user@example.com', password: 'wrong')
      end.to raise_error(Object.const_get(error_name)) { |error|
        expect(error.message).to eq('contract failure')
        expect(error.status).to eq(status)
        expect(error.code).to eq('contract_code')
        expect(error.retry_after).to eq(status == 429 ? 17 : nil)
      }
    end
  end

  it 'maps a no-status network failure without exposing its raw cause', :aggregate_failures do
    failure = SocketError.new('connection failed')
    client = Volcano::Client.new(anon_key: 'anon-key', _transport: ErrorTransport.new(failure))

    expect do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
    end.to raise_error(Volcano::Error::TransportError) { |error|
      expect(error.status).to be_nil
      expect(error.code).to be_nil
      expect(error.retry_after).to be_nil
      expect(error.cause).to be_nil
    }
  end
end
