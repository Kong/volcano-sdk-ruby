# frozen_string_literal: true

require 'volcano'

error = Volcano::Error::RateLimitedError.new(17)
error.missing_method
