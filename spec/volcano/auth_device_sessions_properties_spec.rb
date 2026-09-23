# frozen_string_literal: true

require 'base64'
require 'json'

RSpec.describe Volcano::Auth do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', access_token: 'access', _transport: transport) }

  def response(status, body = nil)
    Volcano::Transport::Response.new(status: status, body: body, headers: {}, data: nil)
  end

  def access_token_with_session_id(session_id)
    encoded = Base64.urlsafe_encode64(JSON.generate({ 'session_id' => session_id }), padding: false)
    "header.#{encoded}.signature"
  end

  it 'preserves requested page and limit values in every complete page response' do
    positive = PropCheck::Generators.choose(1..500)
    generator = PropCheck::Generators.tuple(positive, positive, positive)
    check_property(generator) do |page, limit, total|
      body = { 'sessions' => [], 'page' => page, 'limit' => limit,
               'total' => total, 'total_pages' => (total.to_f / limit).ceil }
      allow(transport).to receive(:auth_get_my_sessions).with(
        authorization: 'access', page: page, limit: limit
      ).and_return(response(200, body))

      result = client.auth.list_sessions(page: page, limit: limit)
      expect(result.to_h).to eq(sessions: [], total: total, page: page, limit: limit,
                                total_pages: (total.to_f / limit).ceil)
    end
  end

  it 'clears the matching current session for arbitrary case-insensitive session IDs' do
    check_property(PropCheck::Generators.choose(0..((1 << 128) - 1))) do |number|
      digits = format('%032x', number)
      session_id = [digits[0, 8], digits[8, 4], digits[12, 4], digits[16, 4], digits[20, 12]].join('-')
      client.auth.current_session = Volcano::Session.new(
        access_token: access_token_with_session_id(session_id), refresh_token: 'refresh', user_id: 'user'
      )
      allow(transport).to receive(:auth_delete_my_session).with(
        authorization: client.current_session.access_token, session_id: session_id.upcase
      ).and_return(response(204))

      client.auth.delete_session(session_id.upcase)
      expect(client.current_session).to be_nil
    end
  end
end
