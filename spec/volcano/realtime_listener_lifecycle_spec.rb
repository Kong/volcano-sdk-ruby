# frozen_string_literal: true

require 'async'
require 'async/queue'
require_relative '../support/fake_realtime'

RSpec.describe Volcano::Realtime do
  let(:socket) { SpecSupport::FacadeSocket.new }
  let(:client) do
    instance = Volcano::Client.new(
      anon_key: 'anon-key', _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    instance.auth.sign_in(email: 'user@example.com', password: 'secret')
    instance
  end

  %i[on_connect on_disconnect on_error].each do |method|
    it "rejects a missing #{method} handler" do
      expect { client.realtime.public_send(method) }
        .to raise_error(ArgumentError, 'callback or block is required')
    end

    it "rejects a non-callable #{method} handler" do
      expect { client.realtime.public_send(method, Object.new) }
        .to raise_error(ArgumentError, 'callback must respond to call')
    end
  end

  %i[broadcast presence postgres].each do |type|
    it "rejects unsupported events on a #{type} channel" do
      channel = client.realtime.channel('room', type: type)
      expect { channel.on('unexpected') { nil } }
        .to raise_error(ArgumentError, 'unsupported realtime event: unexpected')
    end
  end

  %i[presence postgres].each do |type|
    it "does not publish broadcast messages through a subscribed #{type} channel" do
      Async do
        channel = client.realtime.channel('room', type: type)
        channel.subscribe

        expect { channel.send(event: 'message', value: 'blocked') }
          .to raise_error(ArgumentError, 'send is only available for broadcast channels')
        expect(socket.commands.flat_map(&:keys)).not_to include('publish')
      ensure
        client.realtime.disconnect
      end.wait
    end
  end

  def connect_callbacks(events, finished)
    cancellations = []
    client.realtime.on_connect do
      events << :first
      cancellations.fetch(0).call
    end
    cancellations << client.realtime.on_connect { events << :removed }
    client.realtime.on_connect { finished.enqueue(:last) }
  end

  it 'honors cancellation by an earlier connection listener in the same delivery' do
    Async do |task|
      events = []
      finished = Async::Queue.new
      connect_callbacks(events, finished)
      client.realtime.channel('room').subscribe

      expect(task.with_timeout(1) { finished.dequeue }).to eq(:last)
      expect(events).to eq([:first])
    ensure
      client.realtime.disconnect
    end.wait
  end

  def removing_channel(events)
    channel = client.realtime.channel('removed')
    channel.on('message') do
      client.realtime.remove_channel('removed')
      events << :removed
    end
    channel.on('message') { events << :late }
    channel
  end

  it 'stops remaining channel listeners when an earlier listener removes the channel' do
    Async do |task|
      events = []
      finished = Async::Queue.new
      channel = removing_channel(events)
      sentinel = client.realtime.channel('sentinel').on('message') { finished.enqueue(:last) }
      channel.subscribe
      sentinel.subscribe
      socket.publication(channel: channel.name, data: { 'event' => 'message' })
      socket.publication(channel: sentinel.name, data: { 'event' => 'message' })

      expect(task.with_timeout(1) { finished.dequeue }).to eq(:last)
      expect(events).to eq([:removed])
    ensure
      client.realtime.disconnect
    end.wait
  end
end
