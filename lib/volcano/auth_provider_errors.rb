# frozen_string_literal: true

module Volcano
  # Classifies provider-authentication failures without relying on prose when a code exists.
  module AuthProviderErrors
    PROVIDER_NOT_LINKED_CODE = 'provider_not_linked'

    module_function

    def session_failure?(error)
      error.status == 401 && !provider_not_linked?(error)
    end

    def provider_not_linked?(error)
      error.code == PROVIDER_NOT_LINKED_CODE ||
        (!error.code && error.message.downcase.include?('not linked'))
    end
  end
  private_constant :AuthProviderErrors
end
