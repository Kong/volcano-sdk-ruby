Feature: SDK lock contract

  @locks @SDK-LOCKS-001
  Scenario: An acquired lock can be released
    Given a service-role client
    When the client acquires and releases the contract lock
    Then the SDK operation succeeds
    And the released lease is no longer held
