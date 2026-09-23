# frozen_string_literal: true

require 'volcano'

# @type method unsubscribe_once: (Volcano::AuthSubscription) -> nil
def unsubscribe_once(subscription)
  subscription.unsubscribe
end

# @type method empty_subscription: () -> Volcano::AuthSubscription
def empty_subscription
  Volcano::AuthSubscription.new
end
