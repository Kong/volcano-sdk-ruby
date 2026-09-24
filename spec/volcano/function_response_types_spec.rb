# frozen_string_literal: true

RSpec.describe Volcano::FunctionResponse do
  it 'checks and runs the public function response consumer' do
    fixture = File.expand_path('../../tests/types/function_response.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.success?).to be(true), output + errors
    expect { load(fixture) }.not_to raise_error
  end

  it 'rejects invalid function response consumers' do
    fixture = File.expand_path('../../tests/types_invalid/function_response.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Ruby::UnresolvedOverloading')
    expect(output).to include('Ruby::ArgumentTypeMismatch')
    expect(output).to include('Ruby::InsufficientPositionalArguments')
  end

  it 'ships the function response signature in the gem manifest' do
    files = Gem::Specification.load(File.expand_path('../../volcano-sdk.gemspec', __dir__)).files

    expect(files).to include('sig/function_response.rbs')
  end

  it 'preserves nested binary response data across caller mutations' do
    bytes = PropCheck::Generators.array(PropCheck::Generators.choose(0..255), max: 128)
                                 .map { |values| values.pack('C*') }
    check_property(bytes) do |binary|
      original = binary.dup
      body = { 'items' => [{ 'payload' => binary }] }
      response = described_class.new(data: body, status: 200, headers: {}, version: nil)
      binary.replace('changed')

      expect(response.data).to eq('items' => [{ 'payload' => original }])
      expect(response.data.fetch('items').first.fetch('payload').encoding).to eq(Encoding::BINARY)
      expect(response.data.fetch('items').first).to be_frozen
    end
  end

  it 'copies and freezes headers and version independently of the caller' do
    check_property(PropCheck::Generators.printable_string) do |text|
      headers = { 'X-Test' => text }
      version = text.dup
      response = described_class.new(data: nil, status: 200, headers: headers, version: version)
      headers['X-Test'] = 'changed'
      version.replace('changed')

      expect(response.headers).to eq('X-Test' => text)
      expect(response.headers.fetch('X-Test')).to be_frozen
      expect(response.version).to eq(text)
      expect(response.version).to be_frozen
    end
  end
end
