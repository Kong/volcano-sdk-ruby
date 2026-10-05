# frozen_string_literal: true

RSpec.describe Volcano::Realtime do
  it 'checks and runs the packaged realtime facade consumer' do
    fixture = File.expand_path('../../tests/types/realtime_facade.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.success?).to be(true), output + errors
    expect { load(fixture) }.not_to raise_error
  end

  it 'rejects invalid realtime facade consumers' do
    fixture = File.expand_path('../../tests/types_invalid/realtime_facade.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Ruby::ArgumentTypeMismatch')
  end

  it 'rejects a misspelled realtime channel event' do
    fixture = File.expand_path('../../tests/types_invalid/realtime_channel_events.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Ruby::UnresolvedOverloading', 'mesage')
  end

  it 'ships the public realtime facade signature in the gem manifest' do
    files = Gem::Specification.load(File.expand_path('../../volcano-sdk.gemspec', __dir__)).files

    expect(files).to include('sig/realtime.rbs')
  end
end
