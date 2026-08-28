# frozen_string_literal: true

# Public namespace for Volcano SDK authentication.
module Volcano
  # Reconciles API user payloads with the client-owned auth cache.
  module AuthUserState
    private

    def reconcile_payload_user(payload)
      return store_payload_user(payload) if mapping(payload).key?('user')

      refresh_user_or_clear
    end

    def store_payload_user(payload)
      user = build_payload_user(payload)
      @client.store_user(user)
      user
    end

    def build_payload_user(payload)
      build_user(mapping(mapping(payload).fetch('user')))
    rescue KeyError
      raise auth_response_error
    end

    def optional_payload_user(payload)
      build_payload_user(payload) if mapping(payload).key?('user')
    end

    def refresh_user_best_effort
      get_user
    rescue Error::VolcanoError
      nil
    end

    def refresh_user_or_clear
      get_user
    rescue Error::VolcanoError
      @client.clear_user
      nil
    end
  end
  private_constant :AuthUserState
end
