# frozen_string_literal: true

# @type method invalid_profile: (Volcano::Auth) -> void
def invalid_profile(auth)
  auth.request_email_change(new_email: 7)
  auth.confirm_email_change(token: nil)
  auth.update_user(metadata: { 'theme' => Object.new })
end
