# frozen_string_literal: true

module Volcano
  # Runs queued auth-state callbacks outside session coordination locks.
  module AuthNotificationDispatch
    private

    def run_auth_notifications(notifications)
      notifications.each do |notification|
        notification.call
        nil
      end
    end
  end
  private_constant :AuthNotificationDispatch
end
