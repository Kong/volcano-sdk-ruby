# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::Client do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { described_class.new(anon_key: 'anon', access_token: 'supplied-access', _transport: transport) }
  let(:profile) { { 'id' => 'user', 'email' => 'user@example.com', 'status' => 'active' } }

  def response(status, body)
    Volcano::Transport::Response.new(status: status, body: body, headers: {}, data: nil)
  end

  it 'keeps identity unknown until validating the supplied token with the server' do
    initial = client.current_session
    expect(initial.to_h).to eq(access_token: 'supplied-access', refresh_token: nil, user_id: nil, user: nil)
    allow(transport).to receive(:auth_get_user).with(authorization: 'supplied-access')
                                               .and_return(response(200, 'user' => profile))

    expect(client.auth.user.id).to eq('user')
    expect(client.current_session.to_h).to eq(initial.to_h.merge(user_id: 'user', user: profile))
    expect(initial.user_id).to be_nil
    expect(client.current_session.user_id).to be_frozen
  end

  it 'retains an invalid token until local sign-out' do
    allow(transport).to receive(:auth_get_user).and_return(response(401, 'error' => 'expired supplied token'))
    initial = client.current_session
    expect { client.auth.user }.to raise_error(Volcano::Error::AuthenticationError, /expired supplied token/)
    expect { client.auth.refresh_session }.to raise_error(Volcano::Error::AuthenticationError, /No refresh token/)
    expect(client.current_session).to equal(initial)
    client.auth.sign_out
    expect(client.current_session).to be_nil
    expect(transport).to have_received(:auth_get_user).once
  end

  it 'owns mutable supplied credentials' do
    access = +'access'
    refresh = +'refresh'
    bootstrapped = described_class.new(anon_key: 'anon', access_token: access, refresh_token: refresh,
                                       _transport: transport)
    access.replace('changed')
    refresh.replace('changed')
    expect(bootstrapped.current_session.access_token).to eq('access')
    expect(bootstrapped.current_session.refresh_token).to eq('refresh')
  end

  it 'can refresh when the caller supplied a refresh token' do
    bootstrapped = described_class.new(anon_key: 'anon', access_token: 'old', refresh_token: 'refresh',
                                       _transport: transport)
    allow(transport).to receive(:auth_get_user).with(authorization: 'old').and_return(response(401,
                                                                                               'error' => 'expired'))
    refreshed = response(200, 'access_token' => 'new', 'refresh_token' => 'rotated', 'user' => profile)
    allow(transport).to receive(:auth_refresh).with(authorization: 'anon', refresh_token: 'refresh')
                                              .and_return(refreshed)
    allow(transport).to receive(:auth_get_user).with(authorization: 'new').and_return(response(200, 'user' => profile))
    expect(bootstrapped.auth.user.id).to eq('user')
    expect(bootstrapped.current_session.refresh_token).to eq('rotated')
    expect(transport).to have_received(:auth_refresh).once
  end

  it 'does not overwrite a replacement session with the bootstrap profile' do
    replacement = Volcano::Session.new('replacement', 'refresh', 'user')
    allow(transport).to receive(:auth_get_user) do
      client.auth.current_session = replacement
      response(200, 'user' => profile)
    end
    expect { client.auth.user }.to raise_error(Volcano::Error::SessionChangedError)
    expect(client.current_session).to eq(replacement)
  end

  it 'does not change identity after validating the first profile' do
    allow(transport).to receive(:auth_get_user).and_return(response(200, 'user' => profile),
                                                           response(200, 'user' => profile.merge('id' => 'other')))
    client.auth.user
    expect { client.auth.user }.to raise_error(Volcano::Error::AuthenticationError, /different user/)
    expect(client.current_session.user_id).to eq('user')
  end

  it 'keeps complete session adoption strict' do
    initial = client.current_session
    expect { client.auth.current_session = initial }.to raise_error(ArgumentError, /complete/)
    expect(client.current_session).to equal(initial)
  end

  ['', ' '].each do |access|
    it "rejects the empty access token #{access.inspect}" do
      expect { described_class.new(anon_key: 'anon', access_token: access) }
        .to raise_error(ArgumentError, 'access_token must be a non-empty string')
    end
  end

  it 'rejects a refresh token without an access token' do
    expect do
      described_class.new(anon_key: 'anon', refresh_token: 'refresh')
    end.to raise_error(ArgumentError, /access_token/)
  end

  [false, true].each do |enrich_during_refresh|
    it "rejects another user's refresh when profile enrichment happens during refresh: #{enrich_during_refresh}" do
      bootstrapped = described_class.new(anon_key: 'anon', access_token: 'access', refresh_token: 'refresh',
                                         _transport: transport)
      allow(transport).to receive(:auth_get_user).and_return(response(200, 'user' => profile))
      allow(transport).to receive(:auth_refresh) do
        bootstrapped.auth.user if enrich_during_refresh
        response(200, 'access_token' => 'other-access', 'refresh_token' => 'other-refresh',
                      'user' => profile.merge('id' => 'other-user'))
      end
      bootstrapped.auth.user unless enrich_during_refresh

      expect { bootstrapped.auth.refresh_session }.to raise_error(Volcano::Error::AuthenticationError, /different user/)
      expect(bootstrapped.current_session.user_id).to eq('user')
      expect(bootstrapped.current_session.access_token).to eq('access')
    end
  end

  it 'does not replay a mutation under another user after refresh' do
    bootstrapped = described_class.new(anon_key: 'anon', access_token: 'access', refresh_token: 'refresh',
                                       _transport: transport)
    allow(transport).to receive_messages(
      auth_get_user: response(200, 'user' => profile),
      query_database_insert: response(401, 'error' => 'expired'),
      auth_refresh: response(200, 'access_token' => 'other-access', 'refresh_token' => 'other-refresh',
                                  'user' => profile.merge('id' => 'other-user'))
    )
    bootstrapped.auth.user

    expect { bootstrapped.database('main').from('items').insert(name: 'example').execute }
      .to raise_error(Volcano::Error::AuthenticationError, /expired/)
    expect(transport).to have_received(:query_database_insert).once
    expect(bootstrapped.current_session.user_id).to eq('user')
  end

  [204, 401, 503].product([false, true], [nil, 'another-session-refresh']).each do |status, replace, refresh|
    it "revokes captured access: status #{status}, replacement #{replace}, refresh #{refresh.inspect}" do
      token = "header.#{[{ session_id: 'original-session' }.to_json].pack('m0').tr('+/', '-_').delete('=')}.signature"
      bootstrapped = described_class.new(anon_key: 'anon', access_token: token, refresh_token: refresh,
                                         _transport: transport)
      replacement = Volcano::Session.new('replacement', 'refresh', 'user')
      allow(transport).to receive(:auth_delete_my_session).with(authorization: token,
                                                                session_id: 'original-session') do
        bootstrapped.auth.current_session = replacement if replace
        response(status, status == 204 ? nil : { 'error' => 'revocation failed' })
      end
      if replace || status != 204
        expect { bootstrapped.auth.sign_out }
          .to raise_error(replace ? Volcano::Error::SessionChangedError : Volcano::Error::VolcanoError)
      else
        bootstrapped.auth.sign_out
      end
      expect(transport).to have_received(:auth_delete_my_session).once
      expect(bootstrapped.current_session).to eq(replace ? replacement : nil)
    end
  end
end
