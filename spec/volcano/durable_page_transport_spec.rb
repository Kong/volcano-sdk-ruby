# frozen_string_literal: true

RSpec.describe Volcano::Durable do
  let(:client) do
    Volcano::Client.new(anon_key: 'anon', access_token: 'access', api_url: 'https://api.test.volcano.dev')
  end
  let(:empty_page) { { 'data' => [], 'page' => 1, 'limit' => 20, 'total' => 0, 'has_more' => false } }

  %w[data page limit total has_more].each do |field|
    it "rejects an HTTP page without #{field}" do
      respond(empty_page.except(field))

      expect { client.durable.list('project', 'function') }
        .to raise_error(TypeError, 'Expected a complete durable execution page')
    end
  end

  values = [nil, 'invalid', {}, []]
  %w[page limit total has_more].product(values).each do |field, value|
    it "rejects #{field}: #{value.inspect} without generated coercion" do
      respond(empty_page.merge(field => value))

      expect { client.durable.list('project', 'function') }
        .to raise_error(TypeError, 'Expected a complete durable execution page')
    end
  end

  [nil, 'invalid', {}, false].each do |data|
    it "rejects malformed HTTP data: #{data.inspect}" do
      respond(empty_page.merge('data' => data))

      expect { client.durable.list('project', 'function') }
        .to raise_error(TypeError, 'Expected a complete durable execution page')
    end
  end

  [true, false].each do |has_more|
    it "preserves a complete empty HTTP page with has_more: #{has_more}" do
      respond(empty_page.merge('has_more' => has_more))

      expect(client.durable.list('project', 'function'))
        .to have_attributes(executions: [], page: 1, limit: 20, total: 0, has_more: has_more)
    end
  end

  it 'builds typed executions from an uncoerced HTTP page' do
    respond(empty_page.merge('data' => [execution], 'total' => 1))

    page = client.durable.list('project', 'function')

    expect(page.executions.first).to have_attributes(id: 'execution', created_at: Time.utc(2026, 1, 1))
    expect(page.executions).to be_frozen
  end

  private

  def execution
    { 'id' => 'execution', 'function_id' => 'function', 'name' => 'job', 'status' => 'running',
      'region' => 'aws-us-east-1', 'created_at' => '2026-01-01T00:00:00Z' }
  end

  def respond(payload)
    response = Typhoeus::Response.new(
      code: 200, return_code: :ok, headers: { 'Content-Type' => 'application/json' }, body: JSON.generate(payload)
    )
    expect(response).to be_success
    allow(Typhoeus::Request).to receive(:new).and_return(
      instance_double(Typhoeus::Request, run: response, options: {})
    )
  end
end
