# frozen_string_literal: true

RSpec.describe Volcano::Realtime::Channel do
  let(:client) { Volcano::Client.new(anon_key: 'anon-key') }

  after { client.realtime.disconnect }

  it 'rejects a non-callable broadcast callback when it is registered' do
    channel = client.realtime.channel('room')

    expect { channel.on('message', Object.new) }
      .to raise_error(ArgumentError, 'callback must respond to call')
    expect(channel.on('message') { nil }).to be(channel)
  end

  it 'rejects a non-callable Postgres callback when it is registered' do
    channel = client.realtime.channel('items', type: :postgres)

    expect { channel.on_postgres_changes('INSERT', schema: 'public', table: 'items', callback: Object.new) }
      .to raise_error(ArgumentError, 'callback must respond to call')
    expect(channel.on_postgres_changes('INSERT', schema: 'public', table: 'items') { nil }).to be(channel)
  end

  it 'rejects an unknown event before accepting its callback' do
    channel = client.realtime.channel('room')

    expect { channel.on('mesage') { nil } }
      .to raise_error(ArgumentError, 'unsupported realtime event: mesage')
  end
end
