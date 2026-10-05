# frozen_string_literal: true

Volcano::LinkedOAuthProvider.new(provider: 'github', linked_at: 'yesterday', updated_at: Time.now)
Volcano::LinkedOAuthProvider.new(provider: 'github', linked_at: Time.now)
Volcano::LinkedOAuthProvider['github', Time.now, Time.now].with(updated_at: 1)

Volcano::OAuthProviderTokenStatus.new(message: 'ready', provider: 'github', expires_in: '3600')
Volcano::OAuthProviderTokenStatus['ready', 'github', 3600].with(provider: 1)
Volcano::OAuthProviderTokenStatus.new(message: 'ready', provider: 'github')
