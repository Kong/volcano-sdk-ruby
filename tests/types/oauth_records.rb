# frozen_string_literal: true

require 'volcano'

now = Time.utc(2026, 9, 2, 12)
provider = Volcano::LinkedOAuthProvider.new(provider: 'github', linked_at: now, updated_at: now)
raise 'Wrong provider' unless provider.provider == 'github' && provider.linked_at == now
raise 'Wrong members' unless Volcano::LinkedOAuthProvider.members == %i[provider linked_at updated_at]

updated_provider = Volcano::LinkedOAuthProvider['github', now, now].with(provider: 'google')
raise 'Wrong provider update' unless updated_provider.provider == 'google'
raise 'Wrong provider snapshot' unless updated_provider.to_h[:linked_at] == now
raise 'Wrong provider tuple' unless updated_provider.deconstruct == ['google', now, now]
raise 'Wrong provider keys' unless updated_provider.deconstruct_keys([:provider])[:provider] == 'google'

mapped_provider = updated_provider.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong mapped provider' unless mapped_provider['provider'] == 'google'

status = Volcano::OAuthProviderTokenStatus.new(message: 'ready', provider: 'github', expires_in: 3600)
raise 'Wrong status' unless status.expires_in == 3600 && status.message == 'ready'
raise 'Wrong status members' unless Volcano::OAuthProviderTokenStatus.members == %i[message provider expires_in]

updated_status = Volcano::OAuthProviderTokenStatus['ready', 'github', 3600].with(expires_in: 1800)
raise 'Wrong status update' unless updated_status.expires_in == 1800
raise 'Wrong status snapshot' unless updated_status.to_h[:provider] == 'github'
raise 'Wrong status tuple' unless updated_status.deconstruct == ['ready', 'github', 1800]
raise 'Wrong status keys' unless updated_status.deconstruct_keys([:expires_in])[:expires_in] == 1800

mapped_status = updated_status.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong mapped status' unless mapped_status['expires_in'] == '1800'
