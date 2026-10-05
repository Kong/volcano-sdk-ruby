# frozen_string_literal: true

# @type method invalid_unsubscribe: (Volcano::AuthSubscription) -> nil
def invalid_unsubscribe(subscription)
  subscription.unsubscribe(:unexpected)
end
