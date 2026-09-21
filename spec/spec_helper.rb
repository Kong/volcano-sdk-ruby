# frozen_string_literal: true

require 'volcano'
require_relative 'support/test_integrity'

RSpec.configure do |config|
  # Function name resolutions are cached process-wide; keep examples independent.
  config.before { Volcano::FunctionResolution.clear }
end
