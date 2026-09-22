# frozen_string_literal: true

target :sdk do
  signature 'sig', 'sig_dev'
  check 'lib/volcano/errors.rb'
  check 'lib/volcano/connection_string.rb'
  check 'lib/volcano/lock_lease_clock.rb'
  library 'uri'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end

target :consumers do
  signature 'sig'
  check 'tests/types'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end
