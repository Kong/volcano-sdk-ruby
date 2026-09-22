# frozen_string_literal: true

target :sdk do
  signature 'sig'
  check 'lib/volcano/errors.rb'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end

target :consumers do
  signature 'sig'
  check 'tests/types'
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end
