# frozen_string_literal: true

RSpec.describe Volcano::DurableMessage do
  let(:sender) { Volcano::DurableMessageSender.new(type: 'execution') }
  let(:attributes) do
    { id: 'message', execution_id: 'execution', direction: 'out', seq: 1, name: 'progress',
      sender: sender, status: 'published', sent_at: Time.utc(2026) }
  end

  it 'rejects unknown constructor fields' do
    expect { described_class.new(**attributes, unexpected: true) }
      .to raise_error(ArgumentError, 'unknown keywords: unexpected')
  end

  it 'rejects omitted required constructor fields' do
    expect { described_class.new(**attributes.except(:seq, :sent_at)) }
      .to raise_error(ArgumentError, 'missing keywords: seq, sent_at')
  end

  it 'defaults the nullable fields to nil' do
    expect(described_class.new(**attributes)).to have_attributes(data: nil, delivered_at: nil)
  end

  it 'owns immutable copies of caller values', :aggregate_failures do
    name = +'progress'
    data = { 'steps' => [+'build'] }
    user_id = +'user-1'
    message = described_class.new(**attributes, name: name, data: data)
    by_user = Volcano::DurableMessageSender.new(type: 'user', user_id: user_id)
    [name, data.fetch('steps').first, user_id].each { |value| value.replace('changed') }

    expect([message.name, message.data, by_user.user_id]).to eq(['progress', { 'steps' => ['build'] }, 'user-1'])
    expect([message.name, message.data.fetch('steps'), by_user.type, by_user.user_id]).to all(be_frozen)
  end

  it 'freezes a page of messages' do
    expect(Volcano::DurableMessagePage.new(messages: [], has_more: false).messages).to be_frozen
  end

  it 'checks and runs the public message record consumer' do
    fixture = File.expand_path('../../tests/types/durable_message_records.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.success?).to be(true), output + errors
    expect { load(fixture) }.not_to raise_error
  end

  it 'rejects invalid message record consumers' do
    fixture = File.expand_path('../../tests/types_invalid/durable_message_records.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Ruby::ArgumentTypeMismatch')
  end

  it 'ships message record signatures in the gem manifest' do
    files = Gem::Specification.load(File.expand_path('../../volcano-sdk.gemspec', __dir__)).files

    expect(files).to include('sig/durable_message_records.rbs')
  end
end
