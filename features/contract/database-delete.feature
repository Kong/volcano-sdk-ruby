Feature: SDK database delete contract

  @database @SDK-DB-004
  Scenario: An equality-filtered delete returns the removed row
    Given an authenticated client
    When the client deletes its contract row
    Then the SDK operation succeeds
    And exactly the deleted contract row is returned

  @database @SDK-DB-006
  Scenario: An equality-filtered delete with no match returns an empty list
    Given an authenticated client
    When the client deletes a missing contract row
    Then the SDK operation succeeds
    And the mutation returns an empty row list
    And the existing contract row is unchanged
