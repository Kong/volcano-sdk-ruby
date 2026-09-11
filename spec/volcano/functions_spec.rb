# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::Functions do
  let(:client) { Volcano::Client.new(anon_key: 'anon', api_url: 'https://api.test.volcano.dev') }
  let(:resolved) do
    Typhoeus::Response.new(
      code: 200,
      headers: { 'Content-Type' => 'application/json' },
      body: JSON.generate(
        name: 'send-welcome', function_id: '00000000-0000-4000-8000-000000000040', cache_ttl_seconds: 60
      )
    )
  end

  [
    ['{"ok":true}', 'application/json', { 'ok' => true }],
    ['[1,{"ok":true}]', 'application/json', [1, { 'ok' => true }]],
    ['"hello"', 'application/json', 'hello'],
    ['42', 'application/json', 42],
    ['true', 'application/json', true],
    ['null', 'application/json', nil],
    ['hello', 'text/plain', 'hello'],
    ['42', 'text/plain', '42'],
    ['[]', 'text/plain', []],
    ['broken json', 'application/json', 'broken json'],
    ['NaN', 'application/json', 'NaN'],
    ['', 'text/plain', nil]
  ].each do |body, content_type, expected|
    [200, 422].freeze.each do |status|
      context "with #{status} #{content_type} body #{body.inspect}" do
        let(:invoked) do
          Typhoeus::Response.new(
            code: status, body: body,
            headers: { 'Content-Type' => content_type, 'X-Volcano-Version' => 'v2' }
          )
        end

        before do
          allow(Typhoeus::Request).to receive(:new) do |url, _options|
            response = url.end_with?('/functions/resolve') ? resolved : invoked
            instance_double(Typhoeus::Request, run: response, options: {})
          end
        end

        it 'preserves the function body through the generated transport' do
          result = client.functions.invoke('send-welcome')

          expect(result).to have_attributes(data: expected, status: status, version: 'v2')
          expect(result.headers['Content-Type']).to eq(content_type)
          expect(result.data).to be_frozen unless result.data.nil?
        end
      end
    end
  end
end
