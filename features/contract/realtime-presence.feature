Feature: SDK presence membership contract

  @realtime @SDK-REALTIME-003
  Scenario: The original presence handler observes another connection joining and leaving
    Given two authenticated realtime clients
    When one presence client joins and leaves while the other remains subscribed
    Then the SDK operation succeeds
    And both rosters identify the contract user and the original handler observes membership changes
