# frozen_string_literal: true

require_relative 'volcano/version'
require_relative 'volcano/models'
require_relative 'volcano/storage_models'
require_relative 'volcano/auth_state'
require_relative 'volcano/errors'
require_relative 'volcano/redaction'
require_relative 'volcano/transport'
require_relative 'volcano/generated_transport'
require_relative 'volcano/auth'
require_relative 'volcano/auth_sign_up'
require_relative 'volcano/auth_anonymous'
require_relative 'volcano/auth_confirm_email'
require_relative 'volcano/auth_resend_confirmation'
require_relative 'volcano/auth_email_change'
require_relative 'volcano/auth_sessions'
require_relative 'volcano/auth_oauth'
require_relative 'volcano/auth_oauth_sign_in'
require_relative 'volcano/auth_hosted'
require_relative 'volcano/auth_oauth_token'
require_relative 'volcano/auth_oauth_api'
require_relative 'volcano/auth_reset_password_for_email'
require_relative 'volcano/auth_reset_password'
require_relative 'volcano/auth_get_user'
require_relative 'volcano/auth_update_user'
require_relative 'volcano/database'
require_relative 'volcano/storage'
require_relative 'volcano/storage_upload_sessions'
require_relative 'volcano/storage_mutations'
require_relative 'volcano/storage_public_url'
require_relative 'volcano/locks'
require_relative 'volcano/realtime/protocol'
require_relative 'volcano/realtime'
require_relative 'volcano/client'

# Public namespace for the Volcano Ruby SDK.
module Volcano
  private_constant :GeneratedTransport, :Redaction

  Realtime.private_constant :Protocol, :ProtocolDispatch
end
