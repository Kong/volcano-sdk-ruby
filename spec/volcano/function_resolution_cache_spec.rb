# frozen_string_literal: true

RSpec.describe Volcano::FunctionResolution do
  let(:resolution) { described_class::Resolution.new(function_id: 'function', invoke_url: nil) }

  before { allow(described_class).to receive(:now).and_return(100) }

  def store(name, ttl)
    described_class.store('https://api.test', 'credential', name, resolution, ttl)
  end

  def lookup(name)
    described_class.lookup('https://api.test', 'credential', name)
  end

  def fill_cache
    described_class::MAX_ENTRIES.times { |index| store("function-#{index}", 100 + index) }
  end

  it 'evicts the earliest deadline when every entry is still live' do
    fill_cache
    store('overflow', 2000)

    expect(lookup('function-0')).to be_nil
    expect(lookup('function-1').resolution).to eq(resolution)
    expect(lookup('overflow').resolution).to eq(resolution)
  end

  it 'removes expired entries before evicting a live entry' do
    fill_cache
    allow(described_class).to receive(:now).and_return(201)
    store('overflow', 2000)

    expect(lookup('function-0')).to be_nil
    expect(lookup('function-1')).to be_nil
    expect(lookup('function-2').resolution).to eq(resolution)
    expect(lookup('overflow').resolution).to eq(resolution)
  end

  it 'expires an entry exactly at its deadline' do
    store('function', 5)
    allow(described_class).to receive(:now).and_return(105)

    expect(lookup('function')).to be_nil
    expect(lookup('function')).to be_nil
  end

  ['//example.test:80/', 'custom://example.test:80/'].each do |url|
    it "rejects a host and port without an HTTP scheme in #{url.inspect}" do
      expect(described_class.valid_invoke_url(url, 'https://api.test')).to be_nil
    end
  end

  it 'refuses a plaintext endpoint when the API URL has no scheme' do
    expect(described_class.valid_invoke_url('http://example.test/', '//api.test:80')).to be_nil
  end
end
