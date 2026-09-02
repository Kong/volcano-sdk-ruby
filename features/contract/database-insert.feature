Feature: SDK database insert contract

  @database @SDK-DB-002
  Scenario: Insert returns the created row
    Given an authenticated client
    When the client inserts its contract row
    Then the SDK operation succeeds
    And exactly the inserted contract row is returned
