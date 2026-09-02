Feature: SDK database delete contract

  @database @SDK-DB-004
  Scenario: An equality-filtered delete returns the removed row
    Given an authenticated client
    When the client deletes its contract row
    Then the SDK operation succeeds
    And exactly the deleted contract row is returned
