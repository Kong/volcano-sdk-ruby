# frozen_string_literal: true

module Volcano
  RSpec.describe GeneratedTransport do
    let(:functions) { instance_double(Generated::FunctionsApi) }
    let(:logs) { instance_double(Generated::LogsApi) }
    let(:apis) { instance_double(described_class::GeneratedApis, functions: functions, logs: logs) }
    let(:transport) { described_class.new(api_url: 'https://api.test', api_factory: ->(_token) { apis }) }

    [nil, 0, '', 'invalid', '0'].each do |status|
      context "with generated HTTP status #{status.inspect}" do
        let(:failure) { Generated::ApiError.new(code: status, message: 'connection lost') }

        it 'maps invocation failures to transport errors' do
          allow(functions).to receive(:invoke_function_with_http_info).and_raise(failure)

          expect do
            transport.invoke_function(authorization: 'access', function_id: 'function', payload: {})
          end.to(raise_error(Error::TransportError) do |error|
            expect(error.cause).to be(failure)
            expect(error.status).to be_nil
            expect(error.message).to include('connection lost')
          end)
        end

        it 'maps log failures to transport errors' do
          allow(logs).to receive(:search_project_logs_with_http_info).and_raise(failure)

          expect do
            transport.search_project_logs(
              authorization: 'access', project_id: 'project', request: { 'resource' => { 'type' => 'function' } }
            )
          end.to(raise_error(Error::TransportError) do |error|
            expect(error.cause).to be(failure)
            expect(error.status).to be_nil
            expect(error.message).to include('connection lost')
          end)
        end
      end
    end

    [409, '409', '409 conflict'].each do |status|
      context "with generated HTTP status #{status.inspect}" do
        let(:failure) { Generated::ApiError.new(code: status, response_body: '{"error":"conflict"}') }

        it 'preserves the invocation status and function-owned body' do
          allow(functions).to receive(:invoke_function_with_http_info).and_raise(failure)

          response = transport.invoke_function(authorization: 'access', function_id: 'function', payload: {})

          expect(response.status).to eq(409)
          expect(response.body).to eq('error' => 'conflict')
        end

        it 'preserves the status of an ordinary API error' do
          allow(logs).to receive(:search_project_logs_with_http_info).and_raise(failure)

          response = transport.search_project_logs(
            authorization: 'access', project_id: 'project', request: { 'resource' => { 'type' => 'function' } }
          )

          expect(response.status).to eq(409)
          expect(response.body).to eq('error' => 'conflict')
        end
      end
    end

    [nil, 'connection lost'].each do |message|
      it "maps a resolved invocation's status-zero response with message #{message.inspect}" do
        response = instance_double(Typhoeus::Response, code: 0, return_message: message)
        request = instance_double(Typhoeus::Request, run: response)
        allow(Typhoeus::Request).to receive(:new).and_return(request)

        expect do
          transport.invoke_function_url(authorization: 'access', invoke_url: 'https://fn.test', payload: {})
        end.to(raise_error(Error::TransportError, message || 'Volcano request failed') do |error|
          expect(error.status).to be_nil
        end)
      end
    end
  end
end
