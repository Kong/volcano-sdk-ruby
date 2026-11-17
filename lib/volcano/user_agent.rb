# frozen_string_literal: true

require 'rbconfig'

module Volcano
  # Identifies this SDK, its version, and its runtime to Volcano on every
  # request, so the platform can count SDK usage by version.
  module UserAgent
    VALUE = "volcano-sdk-ruby/#{VERSION} (#{RUBY_ENGINE}/#{RUBY_VERSION}; " \
            "#{RbConfig::CONFIG['host_os'].to_s[/\A[a-z]+/] || 'unknown'}/#{RbConfig::CONFIG['host_cpu']})".freeze
  end
  private_constant :UserAgent
end
