# frozen_string_literal: true

# @type method invalid_credentials: (Volcano::Auth) -> void
def invalid_credentials(auth)
  auth.sign_in(email: 12, password: 'secret')
  auth.sign_up(email: 'user@example.test', password: 12)
  auth.sign_in_anonymously(metadata: 'device')
  auth.convert_anonymous(email: 'user@example.test', password: 'secret', metadata: 12)
  auth.confirm_email(token: 12)
  auth.reset_password(token: 'recovery')
  auth.current_session = 'not a session'
end
