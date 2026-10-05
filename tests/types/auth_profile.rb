# frozen_string_literal: true

require 'volcano'

# @type method profile_email: (Volcano::Auth) -> String
def profile_email(auth)
  auth.get_user.email
end

# @type method change_profile: (Volcano::Auth) -> Volcano::User
def change_profile(auth)
  auth.update_user(password: 'new-password', metadata: { display_name: 'Grace', avatar: nil,
                                                         'preferences' => { alerts: [true, false] } })
end

# @type method change_email: (Volcano::Auth) -> Volcano::EmailChangeResult
def change_email(auth)
  auth.request_email_change(new_email: 'new@example.com')
end

# @type method confirm_email: (Volcano::Auth) -> Volcano::User
def confirm_email(auth)
  auth.confirm_email_change(token: 'confirmation-token')
end

# @type method cancel_email: (Volcano::Auth) -> nil
def cancel_email(auth)
  auth.cancel_email_change
end
