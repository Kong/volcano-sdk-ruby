# frozen_string_literal: true

require 'volcano'

# @type method password_sign_in: (Volcano::Auth) -> Volcano::Session
def password_sign_in(auth)
  auth.sign_in(email: 'user@example.test', password: 'secret')
end

# @type method password_sign_up: (Volcano::Auth) -> Volcano::SignUpResult
def password_sign_up(auth)
  auth.sign_up(email: 'user@example.test', password: 'secret', metadata: { plan: 'free' })
end

# @type method anonymous_conversion: (Volcano::Auth) -> Volcano::User
def anonymous_conversion(auth)
  auth.sign_in_anonymously(metadata: { device: 'mobile' })
  auth.convert_anonymous(email: 'user@example.test', password: 'secret')
end

# @type method adopt_credentials: (Volcano::Auth, Volcano::Session) -> Volcano::Session?
def adopt_credentials(auth, session)
  auth.current_session = session
  auth.current_session
end

# @type method credential_messages: (Volcano::Auth) -> nil
def credential_messages(auth)
  auth.confirm_email(token: 'confirmation')
  auth.resend_confirmation(email: 'user@example.test')
  auth.reset_password_for_email(email: 'user@example.test')
  auth.reset_password(token: 'recovery', new_password: 'secret')
end
