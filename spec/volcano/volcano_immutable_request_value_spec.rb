# frozen_string_literal: true

RSpec.describe Volcano do
  let(:snapshotter) { described_class.const_get(:ImmutableRequestValue) }
  let(:bytes) do
    PropCheck::Generators.array(PropCheck::Generators.choose(0..255), max: 128)
                         .map { |values| values.pack('C*') }
  end

  it 'copies and freezes shared nested values without changing their binary encoding' do
    check_property(bytes) do |binary|
      original = binary.dup
      nested = { 'bytes' => binary }
      source = { 'left' => [nested], 'right' => nested }
      snapshot = snapshotter.capture(source)
      binary.replace('changed')
      nested['bytes'] = 'changed'

      expect(snapshot).to eq('left' => [{ 'bytes' => original }], 'right' => { 'bytes' => original })
      expect(snapshot.fetch('left').first.fetch('bytes').encoding).to eq(Encoding::BINARY)
      expect(snapshot.fetch('right').fetch('bytes')).to be_frozen
      expect(snapshot.fetch('left').first).not_to equal(snapshot.fetch('right'))
    end
  end

  it 'rejects direct and indirect cycles while allowing repeated acyclic subtrees' do
    array = []
    array << array
    hash = {}
    hash['array'] = [hash]
    shared = { 'value' => ['ok'] }

    expect { snapshotter.capture(array) }.to raise_error(TypeError, 'Request value contains a cycle')
    expect { snapshotter.capture(hash) }.to raise_error(TypeError, 'Request value contains a cycle')
    expect(snapshotter.capture('a' => shared, 'b' => shared)).to eq('a' => shared, 'b' => shared)
  end

  it 'turns excessive acyclic nesting into a request error' do
    value = []
    10_000.times { value = [value] }

    expect { snapshotter.capture(value) }.to raise_error(TypeError, 'Request value nesting is too deep')
  end

  it 'rejects cyclic function payloads before resolving the function' do
    transport = instance_double(described_class.const_get(:GeneratedTransport))
    allow(transport).to receive(:resolve_function_for_invocation)
    client = described_class::Client.new(anon_key: 'anon', _transport: transport)
    payload = {}
    payload['self'] = payload

    expect { client.functions.invoke('echo', payload) }.to raise_error(TypeError, 'Request value contains a cycle')
    expect(transport).not_to have_received(:resolve_function_for_invocation)
  end
end
