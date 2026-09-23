# frozen_string_literal: true

target :sdk do
  signature 'sig', 'sig_dev'
  check 'lib/volcano/errors.rb'
  check 'lib/volcano/sign_up_result.rb'
  check 'lib/volcano/function_response.rb'
  check 'lib/volcano/connection_string.rb'
  check 'lib/volcano/lock_lease_clock.rb'
  check 'lib/volcano/redaction.rb'
  check 'lib/volcano/storage_public_url.rb'
  library 'base64'
  library 'cgi'
  library 'json'
  library 'uri'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end

target :consumers do
  signature 'sig'
  check 'tests/types'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end
