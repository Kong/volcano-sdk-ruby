# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'

RSpec.describe Volcano do
  it 'exports the client' do
    expect(Volcano::Client.name).to eq('Volcano::Client')
  end

  it 'exports public authentication value objects' do
    expect(
      %i[
        AuthSession AuthorizationRequest EmailChangeResult MessageResult OAuthProvider
        OAuthTokenResult Session SessionPage SignUpResult User
      ].map { |name| described_class.const_get(name).name }
    ).to all(start_with('Volcano::'))
  end

  it 'keeps the generated namespace outside the public constant boundary' do
    expect { Volcano::Generated }.to raise_error(NameError, /private constant/)
  end

  it 'keeps generated transport and realtime protocol details outside the public API', :aggregate_failures do
    client = Volcano::Client.new(anon_key: 'anon-key', _transport: Object.new)

    expect(client.public_methods).not_to include(:transport)
    expect(client.realtime.public_methods).not_to include(:protocol)
    expect { Volcano::GeneratedTransport }.to raise_error(NameError, /private constant/)
    expect { Volcano::Realtime::Protocol }.to raise_error(NameError, /private constant/)
    expect { Volcano::Realtime::ProtocolDispatch }.to raise_error(NameError, /private constant/)
    expect { Volcano::Realtime::ProtocolState }.to raise_error(NameError, /private constant/)
  end

  it 'does not load the Async runtime for a REST-only require' do
    root = File.expand_path('..', __dir__)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      '-I', File.join(root, 'lib'),
      '-e', 'require "volcano"; puts(defined?(Async) || "absent")',
      chdir: root
    )

    expect(status).to be_success
    expect(stdout).to eq("absent\n")
    expect(stderr).not_to include('IO::Buffer is experimental')
  end
end
