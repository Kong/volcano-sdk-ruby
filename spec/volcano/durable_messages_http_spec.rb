# frozen_string_literal: true

RSpec.describe Volcano::DurableMessages do
  let(:client) { Volcano::Client.new(anon_key: 'anon', api_url: 'https://api.test.volcano.dev') }
  let(:messages) { client.durable.messages }
  let(:requests) { [] }
  let(:project) { '00000000-0000-4000-8000-000000000001' }
  let(:execution) { '00000000-0000-4000-8000-000000000061' }

  def application = "https://api.test.volcano.dev/durable-functions/approvals/executions/#{execution}"

  def message
    {
      'id' => 'message', 'execution_id' => execution, 'direction' => 'in', 'seq' => 1, 'name' => 'decision',
      'data' => { 'approved' => true }, 'sender' => { 'type' => 'anon', 'user_id' => nil }, 'status' => 'queued',
      'delivered_at' => nil, 'sent_at' => '2026-10-12T09:00:00Z'
    }
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

  it 'sends to the application route with the client token and idempotency key', :aggregate_failures do
    respond(message, code: 201)

    result = messages.send_message('approvals', execution, 'decision', { 'approved' => true },
                                   idempotency_key: 'decision-1', client_token: 'client-token')

    expect(sent).to eq(
      ["#{application}/messages", :post, {}, '{"name":"decision","data":{"approved":true}}']
    )
    expect([header('Authorization'), header('Idempotency-Key'), header('X-Volcano-Client-Token')])
      .to eq(['Bearer anon', 'decision-1', 'client-token'])
    expect(result).to have_attributes(id: 'message', status: 'queued')
  end

  it 'sends neither header when there is no key or token' do
    respond(message, code: 201)

    messages.send_message('approvals', execution, 'decision')

    expect([header('Idempotency-Key'), header('X-Volcano-Client-Token')]).to eq([nil, nil])
  end

  it 'sends to the project route without a client token' do
    respond(message, code: 200)
    client.auth.current_session = Volcano::Session.new(access_token: 'platform', refresh_token: 'r', user_id: 'u')

    messages.send_message('approvals', execution, 'decision', 'yes', project_id: project, client_token: 'ignored')

    expect(sent.first(2)).to eq(
      ["https://api.test.volcano.dev/projects/#{project}/durable-functions/approvals/executions/#{execution}/messages",
       :post]
    )
    expect([header('Authorization'), header('X-Volcano-Client-Token')]).to eq(['Bearer platform', nil])
  end

  it 'lists with filters as query parameters', :aggregate_failures do
    respond({ 'data' => [message], 'has_more' => false })

    page = messages.list('approvals', execution, direction: 'out', name: 'progress', after: 3, limit: 2,
                                                 client_token: 'client-token')

    expect(sent).to eq(
      ["#{application}/messages", :get, { direction: 'out', name: 'progress', after: 3, limit: 2 }, nil]
    )
    expect(header('X-Volcano-Client-Token')).to eq('client-token')
    expect(page.messages.first.data).to eq('approved' => true)
  end

  it 'lists on the project route' do
    respond({ 'data' => [], 'has_more' => false })
    client.auth.current_session = Volcano::Session.new(access_token: 'platform', refresh_token: 'r', user_id: 'u')

    messages.list('approvals', execution, project_id: project)

    expect(sent).to eq(
      ["https://api.test.volcano.dev/projects/#{project}/durable-functions/approvals/executions/#{execution}/messages",
       :get, {}, nil]
    )
  end

  it 'returns the client token only the creating start receives', :aggregate_failures do
    created = {
      'id' => execution, 'function_id' => 'function', 'name' => 'job', 'status' => 'pending',
      'region' => 'aws-us-east-1', 'created_at' => '2026-10-12T09:00:00Z', 'client_token' => 'client-token'
    }
    respond(created, code: 202)

    expect(client.durable.start('approvals').client_token).to eq('client-token')
    respond(created.except('client_token'), code: 202)
    expect(client.durable.start('approvals', {}, execution_name: 'job').client_token).to be_nil
  end

  it 'masks the client token wherever an execution is inspected', :aggregate_failures do
    respond({
              'id' => execution, 'function_id' => 'function', 'name' => 'job', 'status' => 'pending',
              'region' => 'aws-us-east-1', 'created_at' => '2026-10-12T09:00:00Z', 'client_token' => 'client-token'
            }, code: 202)
    handle = client.durable.start('approvals')
    shown = "#<data Volcano::DurableExecution id=#{execution.inspect}, function_id=\"function\", name=\"job\", " \
            'status="pending", region="aws-us-east-1", created_at=2026-10-12 09:00:00 UTC, result=nil, ' \
            'result_expired=nil, error=nil, completed_at=nil, client_token=[REDACTED]>'

    expect(handle.inspect).to eq(shown)
    expect(handle.to_s).to eq(shown)
    expect(PP.pp(handle, +'')).to eq("#{shown}\n")
    expect(handle.with(client_token: nil).inspect).to end_with('client_token=nil>')
  end

  { 404 => Volcano::Error::NotFoundError, 409 => Volcano::Error::ConflictError }.each do |code, error|
    it "raises #{error} for an HTTP #{code} send" do
      respond({ 'error' => 'refused', 'code' => 'execution_not_running' }, code: code)

      expect { messages.send_message('approvals', execution, 'decision') }.to raise_error(error, 'refused') do |raised|
        expect(raised).to have_attributes(status: code, code: 'execution_not_running')
      end
    end
  end
end
