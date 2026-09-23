# frozen_string_literal: true

module Volcano
  # Rejects stale or replaced auth-session lineages.
  module AuthSessionBinding
    private

    def owned_session_binding(binding)
      active = @client.capture_session_binding
      raise Error::AuthenticationError, 'No active session' if rejected_refresh?(binding, active)

      _, active_lineage, current = active
      raise Error::SessionChangedError unless current && active_lineage == binding[1]

      [active.first, active_lineage, current]
    end

    def rejected_refresh?(binding, active)
      generation, lineage, = binding
      @client.refresh_rejected?(generation, lineage) &&
        active.first == generation + 1 && active.last.nil?
    end
  end
  private_constant :AuthSessionBinding
end
