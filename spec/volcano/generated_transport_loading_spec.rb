# frozen_string_literal: true

require 'open3'

module Volcano
  RSpec.describe GeneratedTransport do
    it 'normalizes a root API path before constructing OAuth URLs' do
      transport = described_class.new(api_url: 'https://api.example.test/')

      url = transport.auth_oauth_authorization_url(
        anon_key: 'anon', provider: 'github', redirect_url: nil, client_state: nil
      )

      expect(URI(url).host).to eq('api.example.test')
      expect(URI(url).path).to eq('/auth/oauth/github/authorize')
    end

    it 'reuses an existing generated-client load path when the SDK loads' do
      source = <<~RUBY
        require 'json'
        generated_path = File.expand_path('lib/volcano/generated/lib')
        $LOAD_PATH.unshift(generated_path)
        require 'volcano'
        puts JSON.generate(copies: $LOAD_PATH.count(generated_path), version: Volcano::VERSION)
      RUBY

      output, errors, status = Open3.capture3(Gem.ruby, '-Ilib', '-r./spec/support/subprocess_coverage', '-e', source)

      expect(status).to be_success, errors
      expect(JSON.parse(output)).to eq('copies' => 1, 'version' => VERSION)
    end
  end
end
