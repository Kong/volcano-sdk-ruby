# frozen_string_literal: true

require 'digest'
require 'json'
require 'open3'
require 'spec_helper'
require 'tmpdir'
require 'rubygems/package'

RSpec.describe 'shared SDK contract bindings' do
  let(:expected_hashes) do
    {
      'auth.feature' => '6e6bcc6244bbdb9b1c141a3f0d8f1256d2be0057429457084a094ed98cbcbd07',
      'database.feature' => '4685b29357a621068b25984ff0de29cd4c504eebe5cfb597f0b999e29878a668',
      'locks.feature' => '76fa31f9a7c203e33b367e5ca1467b2334e7c85c960de8d5cab8638920137411',
      'realtime.feature' => 'e65862e27656cdd0afa8e552cb5a628d9831568e3299711e572ccd4f6b750696',
      'storage.feature' => '0772d46691d2a158e752d19cea995ff79db960fc3774c799ebdf081e19424d82'
    }.freeze
  end

  it 'vendors all five shared feature files byte-for-byte' do
    feature_dir = File.expand_path('../features/contract', __dir__)
    actual = Dir[File.join(feature_dir, '*.feature')].to_h do |path|
      [File.basename(path), Digest::SHA256.file(path).hexdigest]
    end

    expect(actual).to eq(expected_hashes)
  end

  it 'requires an absolute contract fixture path' do
    require_relative '../features/support/fixture'

    expect { VolcanoContract.load_fixture('relative.json') }.to raise_error(
      ArgumentError,
      'VOLCANO_SDK_CONTRACT_FIXTURE must be an absolute path'
    )
  end

  it 'requires the contract fixture to have mode 0600' do
    require_relative '../features/support/fixture'
    path = File.join(Dir.tmpdir, "volcano-contract-fixture-#{Process.pid}.json")
    File.write(path, JSON.generate('api_url' => 'http://localhost:8000'))
    File.chmod(0o644, path)

    expect { VolcanoContract.load_fixture(path) }.to raise_error(
      SecurityError,
      'VOLCANO_SDK_CONTRACT_FIXTURE must have mode 0600'
    )
  ensure
    File.unlink(path) if path && File.exist?(path)
  end

  it 'packages the facade and generated runtime without generator scaffolding' do
    root = File.expand_path('..', __dir__)
    Dir.mktmpdir('volcano-ruby-gem') do |directory|
      gem_path = File.join(directory, 'volcano-sdk.gem')
      stdout, stderr, status = Open3.capture3(
        'gem', 'build', 'volcano-sdk.gemspec', '--output', gem_path,
        chdir: root
      )
      expect(status).to be_success, "#{stdout}\n#{stderr}"

      files = Gem::Package.new(gem_path).spec.files
      expect(files).to include(
        'LICENSE',
        'README.md',
        'lib/volcano.rb',
        'lib/volcano/generated_transport_support.rb',
        'lib/volcano/generated/lib/volcano-generated.rb',
        'lib/volcano/generated/lib/volcano-generated/api_client.rb',
        'lib/volcano/realtime/protocol_io.rb'
      )
      expect(files.grep(%r{\Alib/volcano/generated/(?!lib/)})).to be_empty
    end
  end
end
