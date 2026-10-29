# frozen_string_literal: true

# Reading and stopping an execution on the application route, through the
# generated client down to the request it builds.
RSpec.describe Volcano::Durable do
  let(:client) { Volcano::Client.new(anon_key: 'anon', api_url: 'https://api.test.volcano.dev') }
  let(:requests) { [] }
  let(:execution_id) { '00000000-0000-4000-8000-000000000061' }
  let(:route) { "https://api.test.volcano.dev/durable-functions/charge-order/executions/#{execution_id}" }

  def execution(**overrides)
    {
      'id' => execution_id, 'function_id' => '00000000-0000-4000-8000-000000000062', 'name' => 'order-9',
      'status' => 'running', 'region' => 'aws-us-east-1', 'created_at' => '2026-10-12T09:00:00Z'
    }.merge(overrides.transform_keys(&:to_s))
  end

  def respond(payload, code: 200)
    response = Typhoeus::Response.new(
      code: code, return_code: :ok, headers: { 'Content-Type' => 'application/json' }, body: JSON.generate(payload)
    )
    allow(Typhoeus::Request).to receive(:new) do |url, options|
      requests << [url, options]
      instance_double(Typhoeus::Request, run: response, options: {})
    end
  end

  def sent
    url, options = requests.fetch(0)
    [url, options.fetch(:method), options.fetch(:params), options[:body]]
  end

  def header(name)
    requests.fetch(0).last.fetch(:headers).transform_keys(&:to_s)[name]
  end

  it 'reads an execution with the anon key and its client token', :aggregate_failures do
    respond(execution(status: 'succeeded', completed_at: '2026-10-12T09:01:00Z', result: { 'charge' => 'charge-1' }))

    result = client.durable.get_from_application('charge-order', execution_id, client_token: 'client-token')

    expect(sent).to eq([route, :get, {}, nil])
    expect([header('Authorization'), header('X-Volcano-Client-Token')]).to eq(['Bearer anon', 'client-token'])
    expect(result).to have_attributes(
      id: execution_id, status: 'succeeded', completed_at: Time.utc(2026, 10, 12, 9, 1), client_token: nil
    )
    expect(result.result).to eq('charge' => 'charge-1')
  end

  it 'stops an execution with the anon key and its client token', :aggregate_failures do
    respond(execution)

    result = client.durable.stop_from_application('charge-order', execution_id, client_token: 'client-token')

    expect(sent).to eq(["#{route}/stop", :post, {}, nil])
    expect([header('Authorization'), header('X-Volcano-Client-Token')]).to eq(['Bearer anon', 'client-token'])
    expect(result).to have_attributes(id: execution_id, status: 'running')
  end

  it 'sends no client token when none is given', :aggregate_failures do
    client.auth.current_session = Volcano::Session.new(access_token: 'user-token', refresh_token: 'r', user_id: 'u')
    respond(execution)
    client.durable.get_from_application('charge-order', execution_id)
    respond(execution(status: 'stopped'))
    client.durable.stop_from_application('charge-order', execution_id)

    expect(requests.map { |url, options| [url, options.fetch(:method)] }).to eq(
      [[route, :get], ["#{route}/stop", :post]]
    )
    requests.map(&:last).each do |options|
      headers = options.fetch(:headers).transform_keys(&:to_s)
      expect(headers['Authorization']).to eq('Bearer user-token')
      expect(headers).not_to have_key('X-Volcano-Client-Token')
    end
  end

  it 'sends the service key when there is no session' do
    service_client = Volcano::Client.new(
      anon_key: 'anon', service_key: 'service', api_url: 'https://api.test.volcano.dev'
    )
    respond(execution)

    service_client.durable.get_from_application('charge-order', execution_id)

    expect(header('Authorization')).to eq('Bearer service')
  end

  # A service key scoped to a list without `*` reaches an execution only with
  # its client token, so the token goes out with a service key too.
  it 'sends the client token with the service key', :aggregate_failures do
    service_client = Volcano::Client.new(
      anon_key: 'anon', service_key: 'service', api_url: 'https://api.test.volcano.dev'
    )
    respond(execution)
    service_client.durable.get_from_application('charge-order', execution_id, client_token: 'client-token')
    respond(execution(status: 'stopped'))
    service_client.durable.stop_from_application('charge-order', execution_id, client_token: 'client-token')

    expect(requests.map { |url, options| [url, options.fetch(:method)] }).to eq(
      [[route, :get], ["#{route}/stop", :post]]
    )
    requests.map(&:last).each do |options|
      headers = options.fetch(:headers).transform_keys(&:to_s)
      expect(headers.values_at('Authorization', 'X-Volcano-Client-Token')).to eq(['Bearer service', 'client-token'])
    end
  end

  { get_from_application: :get, stop_from_application: :post }.each do |operation, method|
    it "raises NotFoundError when #{operation} reaches no execution", :aggregate_failures do
      respond({ 'error' => 'durable execution not found' }, code: 404)

      expect { client.durable.public_send(operation, 'charge-order', execution_id, client_token: 'stale') }
        .to raise_error(Volcano::Error::NotFoundError, 'durable execution not found') do |error|
          expect(error).to have_attributes(status: 404, code: nil)
        end
      expect(sent.first(2)).to eq([operation == :get_from_application ? route : "#{route}/stop", method])
    end
  end

  it 'raises ConflictError when a stop reaches an execution that has not started' do
    respond({ 'error' => 'durable execution was never started' }, code: 409)

    expect { client.durable.stop_from_application('charge-order', execution_id, client_token: 'client-token') }
      .to raise_error(Volcano::Error::ConflictError, 'durable execution was never started') do |error|
        expect(error).to have_attributes(status: 409, code: nil)
      end
  end
end
