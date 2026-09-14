# frozen_string_literal: true

require 'volcano'

RSpec.configure do |config|
  # Function name resolutions are cached process-wide; keep examples independent.
  config.before { Volcano::FunctionResolution.clear }
end
