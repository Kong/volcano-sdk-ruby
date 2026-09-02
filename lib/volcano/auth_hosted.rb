# frozen_string_literal: true

require 'openssl'
require 'uri'

module Volcano
  # Builds URLs for Volcano's managed hosted-auth pages.
  class Auth
    HOSTED_AUTH_ACTIONS = %w[login signup forgot-password].freeze
    private_constant :HOSTED_AUTH_ACTIONS

    def get_hosted_auth_url(project_id:, state:, action: 'login')
      project = hosted_auth_parameter(project_id).strip
      auth_state = hosted_auth_parameter(state)
      raise ArgumentError, 'Unsupported hosted auth action' unless HOSTED_AUTH_ACTIONS.include?(action)

      query = URI.encode_www_form(action:, anon_key: @client.anon_token, state: auth_state)
      "#{@api_url}/projects/#{URI.encode_uri_component(project)}/auth/hosted?#{query}"
    end

    def adopt_hosted_auth_session(session, state:, expected_state:)
      validate_hosted_auth_callback_state(state, expected_state)
      adopted = owned_complete_session(session)
      @client.store_session(adopted)
      adopted
    end

    private

    def validate_hosted_auth_callback_state(state, expected_state)
      actual = hosted_auth_parameter(state)
      expected = hosted_auth_parameter(expected_state)
      valid = actual.bytesize == expected.bytesize && OpenSSL.fixed_length_secure_compare(actual, expected)
      raise ArgumentError, 'Hosted auth state mismatch' unless valid
    end

    def hosted_auth_parameter(value)
      return value if value.is_a?(String) && !value.strip.empty?

      raise ArgumentError, 'Hosted auth parameters must be non-empty strings'
    end
  end
end
