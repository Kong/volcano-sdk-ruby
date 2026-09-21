# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'json'
require 'spec_helper'
require 'support/protocol_socket'

RSpec.describe Volcano::Realtime do
  let(:protocol_class) { described_class.const_get(:Protocol, false) }

  def presence_frame(event, info)
    JSON.generate('push' => { 'channel' => 'presence:lobby', event => { 'info' => info } })
  end

  it 'isolates a failing presence observer and keeps delivering later events' do
    Async do |task|
      socket = SpecSupport::ProtocolSocket.new
      protocol = protocol_class.new(socket: socket, task: task)
      received = Async::Queue.new
      info = { 'client' => 'client-1', 'user' => 'user-1' }
      protocol.on_presence('presence:lobby') { raise 'observer failed' }
      protocol.on_presence('presence:lobby') { |event, data| received.enqueue([event, data]) }

      socket.receive(presence_frame('join', info), presence_frame('leave', info))

      expect(task.with_timeout(0.2) { received.dequeue }).to eq(['join', info])
      expect(task.with_timeout(0.2) { received.dequeue }).to eq(['leave', info])
      expect(socket).not_to be_closed
    ensure
      protocol&.close
    end.wait
  end
end
