# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/recording_server'

# Function invocation over the real HTTP stack.
#
# These exercise Typhoeus end to end against two local servers on different
# ports: one standing in for the API, one for the resolved function endpoint.
# Running them apart is the point -- an invocation that reached the API port
# would prove the SDK derived the host instead of using the resolved
# invoke_url.
RSpec.describe Volcano::Functions do
  let(:functions_server) { RecordingServer.new { [200, { 'ok' => true }] } }

  def function_id
    '00000000-0000-4000-8000-000000000040'
  end

  def api_server(resolve_payload, status: 200)
    RecordingServer.new do |target|
      target.start_with?('/functions/resolve') ? [status, resolve_payload] : [200, { 'ok' => 'via-api' }]
    end
  end

  def client(api_url)
    Volcano::Client.new(anon_key: 'anon-key', service_key: 'service-key', api_url: api_url, timeout: 5)
  end

  after { functions_server.close }

  it 'resolves once and reaches the resolved host for repeated invocations', :aggregate_failures do
    api = api_server({
                       'name' => 'send-welcome', 'function_id' => function_id,
                       'invoke_url' => "#{functions_server.url}/", 'cache_ttl_seconds' => 300
                     })
    begin
      instance = client(api.url)
      3.times { expect(instance.functions.invoke('send-welcome', { 'user_id' => 'u-1' }).status).to eq(200) }

      expect(api.targets).to eq(['/functions/resolve?name=send-welcome'])
      expect(functions_server.targets).to eq(['/', '/', '/'])
      invoked = functions_server.requests.first
      expect(JSON.parse(invoked.body)).to eq('payload' => { 'user_id' => 'u-1' })
      expect(invoked.authorization).to eq('Bearer service-key')
    ensure
      api.close
    end
  end

  it 'falls back to the API path without a resolved endpoint', :aggregate_failures do
    api = api_server({ 'name' => 'send-welcome', 'function_id' => function_id, 'cache_ttl_seconds' => 300 })
    begin
      expect(client(api.url).functions.invoke('send-welcome').status).to eq(200)

      expect(api.targets).to eq(
        ['/functions/resolve?name=send-welcome', "/functions/#{function_id}/invoke"]
      )
      expect(functions_server.targets).to be_empty
    ensure
      api.close
    end
  end

  it 'does not re-resolve an unknown name on every attempt', :aggregate_failures do
    api = api_server({ 'error' => 'function not found' }, status: 404)
    begin
      instance = client(api.url)
      3.times do
        expect { instance.functions.invoke('missing-function') }
          .to raise_error(Volcano::Error::NotFoundError)
      end

      expect(api.targets).to eq(['/functions/resolve?name=missing-function'])
    ensure
      api.close
    end
  end
end
