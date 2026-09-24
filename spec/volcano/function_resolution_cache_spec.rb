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

  it 'partitions live resolutions by API origin, credential, and function name' do
    text = PropCheck::Generators.printable_string
    check_property(PropCheck::Generators.tuple(text, text, text)) do |origin, credential, name|
      described_class.clear
      key = ["https://#{origin}.test", "token:#{credential}", "function:#{name}"]
      alternate = described_class::Resolution.new(function_id: 'other', invoke_url: nil)
      described_class.store(*key, resolution, 30)
      described_class.store(key[0], "other:#{credential}", key[2], alternate, 30)

      expect(described_class.lookup(*key).resolution).to eq(resolution)
      expect(described_class.lookup(key[0], "other:#{credential}", key[2]).resolution).to eq(alternate)
      expect(described_class.lookup("https://other-#{origin}.test", key[1], key[2])).to be_nil
      expect(described_class.lookup(key[0], key[1], "other:#{name}")).to be_nil
    end
  end

  it 'expires every generated lifetime at its exact monotonic deadline' do
    check_property(PropCheck::Generators.choose(1..3600)) do |ttl|
      described_class.clear
      allow(described_class).to receive(:now).and_return(100)
      store('function', ttl)
      allow(described_class).to receive(:now).and_return(100 + ttl - 1)
      expect(lookup('function').resolution).to eq(resolution)

      allow(described_class).to receive(:now).and_return(100 + ttl)
      expect(lookup('function')).to be_nil
    end
  end

  it 'accepts encoded HTTPS routes and permits HTTP only with a plaintext API' do
    generator = PropCheck::Generators.tuple(
      PropCheck::Generators.choose(1..65_535), PropCheck::Generators.printable_string
    )
    check_property(generator) do |port, route|
      suffix = URI.encode_www_form_component(route)
      secure = "https://function.test:#{port}/#{suffix}"
      plaintext = "http://function.test:#{port}/#{suffix}"

      expect(described_class.valid_invoke_url(secure, 'https://api.test')).to eq(secure)
      expect(described_class.valid_invoke_url(plaintext, 'http://api.test')).to eq(plaintext)
      expect(described_class.valid_invoke_url(plaintext, 'https://api.test')).to be_nil
    end
  end

  it 'detaches negative-cache error metadata from the originating exception' do
    check_property(PropCheck::Generators.printable_string) do |suffix|
      described_class.clear
      allow(described_class).to receive(:now).and_return(100)
      message = "missing:#{suffix}"
      code = "code:#{suffix}"
      original = Volcano::Error::NotFoundError.new(message, status: 404, code: code, retry_after: nil)
      described_class.store_missing('https://api.test', 'first', 'function', original)
      message.replace('changed')
      code.replace('changed')

      cached = described_class.lookup('https://api.test', 'first', 'function')
      failure = described_class.error_for(cached.failure)
      expect(failure.message).to eq("missing:#{suffix}")
      expect(failure.code).to eq("code:#{suffix}")
    end
  end

  it 'partitions remembered misses by credential and expires them after thirty seconds' do
    error = Volcano::Error::NotFoundError.new('missing', status: 404, code: 'missing', retry_after: nil)
    described_class.store_missing('https://api.test', 'first', 'function', error)

    expect(described_class.lookup('https://api.test', 'second', 'function')).to be_nil
    allow(described_class).to receive(:now).and_return(130)
    expect(described_class.lookup('https://api.test', 'first', 'function')).to be_nil
  end
end
