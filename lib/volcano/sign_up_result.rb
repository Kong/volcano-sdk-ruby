# frozen_string_literal: true

module Volcano
  SignUpResult = Data.define(:confirmation_required, :message, :session)

  # Reopen the generated Data class so Steep can check its initializer.
  class SignUpResult
    # @dynamic confirmation_required, message, session, members, with, to_h, deconstruct, deconstruct_keys
    # @dynamic self.[], self.members
    def initialize(confirmation_required:, message:, session: nil)
      super
    end
  end
end
