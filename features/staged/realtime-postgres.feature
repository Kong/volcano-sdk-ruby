Feature: SDK Postgres change delivery contract

  @realtime @SDK-REALTIME-004
  Scenario: Insert and update notifications support automatic rows and lightweight delivery
    Given two authenticated realtime clients
    When the clients observe an inserted and updated contract row
    Then the SDK operation succeeds
    And automatic and lightweight notifications retain metadata and row identity
