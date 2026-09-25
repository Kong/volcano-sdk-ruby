# frozen_string_literal: true

target :sdk do
  signature 'sig', 'sig_dev'
  check 'lib/volcano/errors.rb'
  check 'lib/volcano/sign_up_result.rb'
  check 'lib/volcano/function_response.rb'
  check 'lib/volcano/function_resolution.rb'
  check 'lib/volcano/log_responses.rb'
  check 'lib/volcano/connection_string.rb'
  check 'lib/volcano/redaction.rb'
  library 'base64'
  library 'cgi'
  library 'json'
  library 'uri'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end

target :realtime do
  signature 'sig', 'sig_dev'
  check 'lib/volcano/realtime.rb'
  check 'lib/volcano/realtime'
  library 'base64'
  library 'cgi'
  library 'json'
  library 'securerandom'
  library 'timeout'
  library 'uri'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end

target :core_facades do
  signature 'sig', 'sig_dev'
  check 'lib/volcano.rb'
  check 'lib/volcano/database.rb'
  check 'lib/volcano/durable.rb'
  check 'lib/volcano/durable_models.rb'
  check 'lib/volcano/function_auth.rb'
  check 'lib/volcano/functions.rb'
  check 'lib/volcano/immutable_request_value.rb'
  check 'lib/volcano/logs.rb'
  check 'lib/volcano/models.rb'
  check 'lib/volcano/session.rb'
  check 'lib/volcano/transport.rb'
  check 'lib/volcano/transport_json.rb'
  check 'lib/volcano/user.rb'
  check 'lib/volcano/version.rb'
  library 'json'
  library 'securerandom'
  library 'socket'
  library 'time'
  library 'timeout'
  library 'uri'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end

target :locks do
  signature 'sig', 'sig_dev'
  check 'lib/volcano/lock_lease_clock.rb'
  check 'lib/volcano/lock_guard.rb'
  check 'lib/volcano/lock_auto_renewal.rb'
  check 'lib/volcano/lock_response.rb'
  check 'lib/volcano/locks.rb'
  check 'lib/volcano/lock_renewer.rb'
  check 'lib/volcano/lock_session.rb'
  library 'securerandom'
  library 'time'
  library 'timeout'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end

target :auth_state do
  signature 'sig', 'sig_dev'
  check 'lib/volcano/session_operations.rb'
  check 'lib/volcano/auth_state.rb'
  check 'lib/volcano/auth_state_notifications.rb'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end

target :auth_credentials do
  signature 'sig', 'sig_dev'
  check 'lib/volcano/session_credentials.rb'
  check 'lib/volcano/session_page_mapping.rb'
  library 'base64'
  library 'json'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end

target :auth_lifecycle do
  signature 'sig', 'sig_dev'
  check 'lib/volcano/auth_notification_dispatch.rb'
  check 'lib/volcano/auth_session_binding.rb'
  check 'lib/volcano/auth_refresh.rb'
  check 'lib/volcano/auth_sign_out.rb'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end

target :auth_profile do
  signature 'sig', 'sig_dev'
  check 'lib/volcano/auth_profile_fields.rb'
  check 'lib/volcano/auth_get_user.rb'
  check 'lib/volcano/auth_update_user.rb'
  check 'lib/volcano/auth_email_change.rb'
  library 'json'
  library 'time'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end

target :auth_sessions do
  signature 'sig', 'sig_dev'
  check 'lib/volcano/auth_sessions.rb'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end

target :auth_oauth do
  signature 'sig', 'sig_dev'
  check 'lib/volcano/auth_oauth.rb'
  check 'lib/volcano/auth_oauth_sign_in.rb'
  check 'lib/volcano/auth_hosted.rb'
  check 'lib/volcano/auth_oauth_token.rb'
  check 'lib/volcano/auth_oauth_api.rb'
  library 'json'
  library 'openssl'
  library 'uri'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end

target :storage do
  signature 'sig', 'sig_dev'
  check 'lib/volcano/storage_session_adapter.rb'
  check 'lib/volcano/storage_transport_adapter.rb'
  check 'lib/volcano/storage_object_response.rb'
  check 'lib/volcano/storage.rb'
  check 'lib/volcano/storage_models.rb'
  check 'lib/volcano/storage_upload_models.rb'
  check 'lib/volcano/storage_mutations.rb'
  check 'lib/volcano/storage_resumable_upload.rb'
  check 'lib/volcano/storage_upload_sessions.rb'
  check 'lib/volcano/storage_response.rb'
  check 'lib/volcano/storage_public_url.rb'
  library 'base64'
  library 'cgi'
  library 'json'
  library 'stringio'
  library 'tempfile'
  library 'time'
  library 'uri'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end

target :auth_flows do
  signature 'sig', 'sig_dev'
  check 'lib/volcano/auth_session_construction.rb'
  check 'lib/volcano/auth.rb'
  check 'lib/volcano/auth_sign_up.rb'
  check 'lib/volcano/auth_anonymous.rb'
  check 'lib/volcano/auth_confirm_email.rb'
  check 'lib/volcano/auth_resend_confirmation.rb'
  check 'lib/volcano/auth_reset_password_for_email.rb'
  check 'lib/volcano/auth_reset_password.rb'
  library 'json'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end

target :consumers do
  signature 'sig'
  check 'tests/types'
  library 'stringio'
  library 'tempfile'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end

target :sandboxes do
  signature 'sig', 'sig_dev'
  check 'lib/volcano/sandbox_models.rb'
  check 'lib/volcano/sandbox_request.rb'
  check 'lib/volcano/sandbox_response.rb'
  check 'lib/volcano/sandboxes.rb'
  check 'lib/volcano/sandbox_session.rb'
  check 'lib/volcano/sandbox_files.rb'
  library 'base64'
  library 'securerandom'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end
