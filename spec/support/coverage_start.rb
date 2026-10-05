# frozen_string_literal: true

require 'coverage'

# The gemspec loads version.rb during Bundler setup, before SimpleCov is available.
Coverage.start(lines: true, branches: true)
require 'bundler/setup'
require 'simplecov/autostart'
