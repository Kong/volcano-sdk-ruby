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

  def api_server(resolve_payload, status: 200, resolve_delay: 0)
    RecordingServer.new do |target|
      next [200, { 'ok' => 'via-api' }] unless target.start_with?('/functions/resolve')

      sleep(resolve_delay) if resolve_delay.positive?
      [status, resolve_payload]
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

  it 'shares one resolve across concurrent first invocations', :aggregate_failures do
    api = api_server({
                       'name' => 'send-welcome', 'function_id' => function_id,
                       'invoke_url' => "#{functions_server.url}/", 'cache_ttl_seconds' => 300
                     }, resolve_delay: 0.2)
    begin
      instance = client(api.url)
      callers = Array.new(8) { Thread.new { instance.functions.invoke('send-welcome').status } }

      expect(callers.map(&:value)).to all(eq(200))
      expect(api.targets).to eq(['/functions/resolve?name=send-welcome'])
      expect(functions_server.targets.length).to eq(8)
    ensure
      api.close
    end
  end

  # The first invocation finds the cached identity gone. The platform answers
  # without the dispatch marker, which is the only thing telling this apart from
  # the function itself returning 404.
  def recreated_function_server
    invoked = 0
    RecordingServer.new do |target|
      next resolve_answer if target.start_with?('/functions/resolve')

      invoked += 1
      next [404, { 'error' => 'function not found' }] if invoked == 1

      [200, { 'ok' => true }, { 'X-Volcano-Function-Invoked' => 'true' }]
    end
  end

  def resolve_answer
    [200, { 'name' => 'send-welcome', 'function_id' => function_id, 'cache_ttl_seconds' => 300 }]
  end

  it 'resolves a recreated function again after a platform 404', :aggregate_failures do
    api = recreated_function_server
    begin
      expect(client(api.url).functions.invoke('send-welcome').status).to eq(200)

      expect(api.targets).to eq(
        ['/functions/resolve?name=send-welcome', "/functions/#{function_id}/invoke",
         '/functions/resolve?name=send-welcome', "/functions/#{function_id}/invoke"]
      )
    ensure
      api.close
    end
  end

  it 'returns a function-authored 404 without invoking it twice', :aggregate_failures do
    api = RecordingServer.new do |target|
      next resolve_answer if target.start_with?('/functions/resolve')

      # The function ran and chose 404. Retrying would repeat whatever it did on
      # the way to deciding that.
      [404, { 'error' => 'no such record' }, { 'X-Volcano-Function-Invoked' => 'true' }]
    end
    begin
      expect(client(api.url).functions.invoke('send-welcome').status).to eq(404)

      expect(api.targets).to eq(
        ['/functions/resolve?name=send-welcome', "/functions/#{function_id}/invoke"]
      )
    ensure
      api.close
    end
  end
end
