# frozen_string_literal: true

RSpec.describe Volcano::DurableApproval do
  let(:function) { Volcano::DurableApprovalFunction.new(id: nil, name: 'pipeline') }
  let(:execution) { Volcano::DurableApprovalExecution.new(id: nil, name: 'run', status: nil) }
  let(:attributes) do
    { id: 'approval', status: 'pending', name: 'ship', title: 'Ship?', description: '',
      function: function, execution: execution, requested_at: Time.utc(2026) }
  end

  it 'rejects unknown constructor fields' do
    expect { described_class.new(**attributes, unexpected: true) }
      .to raise_error(ArgumentError, 'unknown keywords: unexpected')
  end

  it 'rejects omitted required constructor fields' do
    expect { described_class.new(**attributes.except(:title, :requested_at)) }
      .to raise_error(ArgumentError, 'missing keywords: title, requested_at')
  end

  it 'defaults the nullable fields to nil' do
    expect(described_class.new(**attributes)).to have_attributes(details: nil, expires_at: nil, decision: nil)
  end

  it 'owns immutable copies of caller values', :aggregate_failures do
    title = +'Ship?'
    details = { 'items' => [+'a'] }
    approval = described_class.new(**attributes, title: title, details: details)
    title.replace('changed')
    details.fetch('items').first.replace('changed')

    expect(approval.title).to eq('Ship?').and be_frozen
    expect(approval.details).to eq('items' => ['a'])
    expect(approval.details.fetch('items')).to be_frozen
  end

  it 'owns immutable copies of nested record values', :aggregate_failures do
    name = +'pipeline'
    comment = +'ok'
    email = +'ops@example.com'
    date = +'2026-10-06'
    decided = Volcano::DurableApprovalDecision.new(
      comment: comment, decided_by: Volcano::DurableApprovalDecider.new(id: 'user', email: email),
      decided_at: Time.utc(2026)
    )
    named = Volcano::DurableApprovalFunction.new(id: 'function', name: name)
    day = Volcano::DurableApprovalDailyCounts.new(date: date, counts: nil)
    [name, comment, email, date].each { |value| value.replace('changed') }

    expect([named.name, decided.comment, decided.decided_by&.email, day.date])
      .to eq(['pipeline', 'ok', 'ops@example.com', '2026-10-06'])
    expect([named.name, decided.comment, decided.decided_at, day.date]).to all(be_frozen)
  end

  it 'freezes a page of approvals' do
    page = Volcano::DurableApprovalPage.new(approvals: [], page: 1, limit: 20, total: 0, has_more: false)

    expect(page.approvals).to be_frozen
  end

  it 'rejects statistics without their window' do
    expect { Volcano::DurableApprovalStats.new(counts: nil, functions: [], other_functions: nil, daily: []) }
      .to raise_error(ArgumentError, 'missing keywords: from, to')
  end

  it 'checks and runs the public approval record consumer' do
    fixture = File.expand_path('../../tests/types/durable_approval_records.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.success?).to be(true), output + errors
    expect { load(fixture) }.not_to raise_error
  end

  it 'rejects invalid approval record consumers' do
    fixture = File.expand_path('../../tests/types_invalid/durable_approval_records.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Ruby::ArgumentTypeMismatch')
  end

  it 'ships approval record signatures in the gem manifest' do
    files = Gem::Specification.load(File.expand_path('../../volcano-sdk.gemspec', __dir__)).files

    expect(files).to include('sig/durable_approval_records.rbs')
  end
end
