# frozen_string_literal: true

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

    private

    def hosted_auth_parameter(value)
      return value if value.is_a?(String) && !value.strip.empty?

      raise ArgumentError, 'Hosted auth parameters must be non-empty strings'
    end
  end
end
