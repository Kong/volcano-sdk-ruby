# frozen_string_literal: true

RSpec.describe Volcano::Client do
  let(:functions) { instance_double(Volcano.const_get(:Generated)::FunctionsApi) }
  let(:logs) { instance_double(Volcano.const_get(:Generated)::LogsApi) }
  let(:apis) do
    instance_double(Volcano.const_get(:GeneratedTransport)::GeneratedApis, functions: functions, logs: logs)
  end
  let(:transport) do
    Volcano.const_get(:GeneratedTransport).new(api_url: 'https://api.test', api_factory: ->(_token) { apis })
  end
  let(:client) { described_class.new(anon_key: 'anon', access_token: 'access', _transport: transport) }

  [nil, '', '{', 'null', '[]'].each do |body|
    it "refuses an incomplete resolution body #{body.inspect} before invoking" do
      allow(functions).to receive(:resolve_function_for_invocation_with_http_info).and_return([body, 200, {}])
      allow(functions).to receive(:invoke_function_with_http_info)

      expect { client.functions.invoke('echo') }.to raise_error(TypeError, 'Expected a complete function response')
      expect(functions).not_to have_received(:invoke_function_with_http_info)
    end

    it "refuses an incomplete log page #{body.inspect}" do
      allow(logs).to receive(:search_project_logs_with_http_info).and_return([body, 200, {}])

      expect do
        client.logs.search('project', 'resource' => { 'type' => 'function' })
      end.to raise_error(TypeError, 'Expected a complete log response')
    end
  end

  [nil, '', '{'].each do |body|
    it "retains HTTP failure status when the generated client returns error body #{body.inspect}" do
      failure = Volcano.const_get(:Generated)::ApiError.new(code: 503, response_body: body, response_headers: nil)
      allow(logs).to receive(:search_project_logs_with_http_info).and_raise(failure)

      expect do
        client.logs.search('project', 'resource' => { 'type' => 'function' })
      end.to(raise_error(Volcano::Error::ServerError) do |error|
        expect(error.status).to eq(503)
        expect(error.message).to eq('Volcano request failed')
      end)
    end
  end
end
