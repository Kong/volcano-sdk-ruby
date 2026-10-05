# frozen_string_literal: true

module Volcano
  # Current-user update behavior for the authentication facade.
  module AuthUpdateUser
    def update_user(password: nil, metadata: nil)
      profile_request do
        request_password = password&.dup&.freeze
        request_metadata = metadata.nil? ? nil : JSON.parse(JSON.generate(Hash(metadata)), freeze: true)
        ->(token) { update_user_response(token, password: request_password, metadata: request_metadata) }
      end
    end

    private

    def update_user_response(access_token, password:, metadata:)
      Transport.invoke do
        @transport.auth_update_user(
          authorization: access_token,
          password: password,
          metadata: metadata
        )
      end
    end
  end
end
