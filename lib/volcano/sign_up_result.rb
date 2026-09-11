# frozen_string_literal: true

module Volcano
  SignUpResult = Data.define(:confirmation_required, :message, :session) do
    def initialize(confirmation_required:, message:, session: nil)
      super
    end
  end
end
