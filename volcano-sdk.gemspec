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
  spec.required_ruby_version = '>= 3.3'
  spec.files = Dir[
    'lib/volcano.rb',
    'lib/volcano/*.rb',
    'lib/volcano/realtime/**/*.rb',
    'lib/volcano/generated/lib/**/*.rb',
    'sig/**/*.rbs',
    'LICENSE',
    'README.md'
  ]
  spec.require_paths = ['lib']
  # Exact versions: CI tests these, and Dependabot proposes each bump.
  spec.add_dependency 'async', '2.46.0'
  spec.add_dependency 'async-http', '0.105.0'
  spec.add_dependency 'async-websocket', '0.30.1'
  spec.add_dependency 'base64', '0.3.0'
  # Explicit-content-type uploads pass Ethon a [filename, type, path] form value
  # that Ethon 0.19 URL-encodes instead of sending as a multipart part.
  spec.add_dependency 'ethon', '0.18.0'
  spec.add_dependency 'io-event', '1.22.1'
  spec.add_dependency 'json', '2.21.2'
  spec.add_dependency 'logger', '1.7.0'
  spec.add_dependency 'protocol-rack', '0.23.0'
  spec.add_dependency 'typhoeus', '1.6.0'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
