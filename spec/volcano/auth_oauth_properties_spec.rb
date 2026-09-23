# frozen_string_literal: true

require 'uri'

RSpec.describe Volcano::Auth do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', access_token: 'access', _transport: transport) }

  it 'round-trips arbitrary reserved characters through hosted-auth URLs' do
    text = PropCheck::Generators.printable_ascii_string(max: 32)
    generator = PropCheck::Generators.tuple(text.map { |value| "p#{value}" }, text.map { |value| "s#{value}" })
    check_property(generator) do |project, state|
      url = URI.parse(client.auth.get_hosted_auth_url(project_id: project, state:))
      encoded_project = url.path.split('/').fetch(2)
      parameters = URI.decode_www_form(url.query).to_h

      expect(URI.decode_uri_component(encoded_project)).to eq(project.strip)
      expect(parameters).to eq('action' => 'login', 'anon_key' => 'anon', 'state' => state)
    end
  end

  it 'rejects equal-length mismatched OAuth states before any exchange' do
    allow(transport).to receive(:auth_oauth_exchange)
    check_property(PropCheck::Generators.choose(0..0xffff_ffff)) do |number|
      actual = format('%08x', number)
      expected = format('%08x', number ^ 1)

      expect do
        client.auth.exchange_oauth_code(
          code: 'code', redirect_to: 'https://app.test/callback', state: actual, expected_state: expected
        )
      end.to raise_error(ArgumentError, 'OAuth state mismatch')
    end
    expect(transport).not_to have_received(:auth_oauth_exchange)
  end
end
