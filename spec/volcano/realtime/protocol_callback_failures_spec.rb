# frozen_string_literal: true

require 'async'
require 'spec_helper'
require 'support/protocol_socket'

ProtocolCallbackFailures = Volcano::Realtime.const_get(:Protocol, false)

RSpec.describe ProtocolCallbackFailures do
  around { |example| Async { example.run }.wait }

  let(:protocol_socket) { SpecSupport::ProtocolSocket.new }
  let(:errors) { Async::Queue.new }
  let(:failures) { Async::Queue.new }
  let(:events) do
    described_class::Events.new(on_close: nil, on_error: ->(error) { errors.enqueue(error) },
                                on_failure: ->(error, connected) { failures.enqueue([error, connected]) })
  end
  let(:protocol) { described_class.new(socket: protocol_socket, task: Async::Task.current, events: events) }

  after { protocol.close }

  it 'closes the socket and rejects further commands after reporting the failure' do
    queue = protocol.instance_variable_get(:@callback_queue)
    allow(queue).to receive(:dequeue).and_raise(IOError, 'callback queue failed')
    queue.enqueue([[], 'join', {}])
    error = Async::Task.current.with_timeout(1) { errors.dequeue }
    failure = Async::Task.current.with_timeout(1) { failures.dequeue }

    expect(error.message).to eq('callback queue failed')
    expect(failure).to eq([error, false])
    expect(protocol_socket).to be_closed
    expect { protocol.presence(channel: 'presence:room') }.to raise_error(Volcano::Realtime::ClosedError)
    expect([errors.empty?, failures.empty?]).to eq([true, true])
  end
end
