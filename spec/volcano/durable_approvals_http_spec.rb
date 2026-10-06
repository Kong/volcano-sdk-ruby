# frozen_string_literal: true

RSpec.describe Volcano::DurableApprovals do
  let(:approvals) do
    Volcano::Client.new(anon_key: 'anon', access_token: 'platform-token', api_url: 'https://api.test.volcano.dev')
                   .durable.approvals
  end
  let(:requests) { [] }
  let(:project) { '00000000-0000-4000-8000-000000000001' }
  let(:approval_id) { '00000000-0000-4000-8000-000000000051' }
  let(:base) { "https://api.test.volcano.dev/projects/#{project}/durable-approvals" }

  def approval
    {
      'id' => approval_id, 'status' => 'approved', 'name' => 'ship-order', 'title' => 'Ship?',
      'description' => '', 'details' => { 'items' => [{ 'sku' => 'a' }] },
      'function' => { 'id' => nil, 'name' => 'order-pipeline' },
      'execution' => { 'id' => nil, 'name' => 'order-1', 'status' => nil },
      'requested_at' => '2026-10-06T12:00:00Z', 'expires_at' => nil,
      'decision' => { 'comment' => 'ok', 'decided_by' => nil, 'decided_at' => '2026-10-06T12:01:00Z' }
    }
  end

  def counts
    { 'requested' => 1, 'pending' => 0, 'approved' => 1, 'denied' => 0, 'expired' => 0, 'cancelled' => 0 }
  end

  def stats
    {
      'from' => '2026-09-06T00:00:00Z', 'to' => '2026-10-06T00:00:00Z', 'counts' => counts,
      'approval_rate' => 1, 'median_seconds_to_decision' => 60, 'p90_seconds_to_decision' => 60,
      'functions' => [], 'other_functions' => counts, 'daily' => [{ 'date' => '2026-10-06', 'counts' => counts }]
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
    [url, options.fetch(:method), options.fetch(:params), options[:body], options.fetch(:headers)['Authorization']]
  end

  it 'lists approvals with filters as query parameters', :aggregate_failures do
    respond({ 'data' => [approval], 'page' => 1, 'limit' => 5, 'total' => 1, 'has_more' => false })

    page = approvals.list(project, status: 'approved', function: 'order-pipeline', limit: 5,
                                   from: Time.utc(2026, 10, 1, 0, 0, 0, 500))

    expect(sent).to eq(
      [base, :get, { status: 'approved', function: 'order-pipeline', from: '2026-10-01T00:00:00.000500000Z',
                     limit: 5 }, nil, 'Bearer platform-token']
    )
    expect(page.approvals.first.details).to eq('items' => [{ 'sku' => 'a' }])
    expect(page.approvals.first.decision).to have_attributes(comment: 'ok', decided_by: nil)
  end

  it 'reads one approval by its id' do
    respond(approval)

    approvals.get(project, approval_id)

    expect(sent).to eq(["#{base}/#{approval_id}", :get, {}, nil, 'Bearer platform-token'])
  end

  it 'reads statistics with their window as query parameters', :aggregate_failures do
    respond(stats)

    stats = approvals.stats(project, to: '2026-10-06T00:00:00Z')

    expect(sent).to eq(["#{base}/stats", :get, { to: '2026-10-06T00:00:00.000000000Z' }, nil, 'Bearer platform-token'])
    expect(stats).to have_attributes(approval_rate: 1.0, daily: [have_attributes(date: '2026-10-06')])
  end

  it 'approves with the comment as the JSON body' do
    respond(approval)

    approvals.approve(project, approval_id, comment: 'ship it')

    expect(sent).to eq(["#{base}/#{approval_id}/approve", :post, {}, '{"comment":"ship it"}', 'Bearer platform-token'])
  end

  it 'denies with an empty JSON object when there is no comment' do
    respond(approval.merge('status' => 'denied'))

    approvals.deny(project, approval_id)

    expect(sent).to eq(["#{base}/#{approval_id}/deny", :post, {}, '{}', 'Bearer platform-token'])
  end

  { 403 => Volcano::Error::PermissionError, 404 => Volcano::Error::NotFoundError,
    409 => Volcano::Error::ConflictError }.each do |code, error|
    it "raises #{error} for an HTTP #{code} decision" do
      respond({ 'error' => 'refused', 'code' => 'approval_decided' }, code: code)

      expect { approvals.approve(project, approval_id) }.to raise_error(error, 'refused') do |raised|
        expect(raised).to have_attributes(status: code, code: 'approval_decided')
      end
    end
  end
end
