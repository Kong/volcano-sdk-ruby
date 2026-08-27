Feature: SDK realtime contract

  @realtime @SDK-REALTIME-001
  Scenario: Broadcast reaches another subscribed client
    Given two authenticated realtime clients
    When one client subscribes and the other publishes the contract message
    Then the SDK operation succeeds
    And the subscriber receives the contract message within 10 seconds
