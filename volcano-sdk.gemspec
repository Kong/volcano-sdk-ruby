# frozen_string_literal: true

require_relative 'lib/volcano/version'

Gem::Specification.new do |spec|
  spec.name = 'volcano-sdk'
  spec.version = Volcano::VERSION
  spec.authors = ['Kong']
  spec.email = ['office@konghq.com']
  spec.summary = 'Official Ruby SDK for Volcano'
  spec.homepage = 'https://github.com/Kong/volcano-sdk-ruby'
  spec.license = 'Apache-2.0'
  spec.required_ruby_version = '>= 3.2'
  spec.files = Dir['lib/**/*', 'LICENSE', 'README.md']
  spec.require_paths = ['lib']
end
