Feature: SDK database update contract

  @database @SDK-DB-003
  Scenario: An equality-filtered update returns the changed row
    Given an authenticated client
    When the client updates its contract row
    Then the SDK operation succeeds
    And exactly the updated contract row is returned

  @database @SDK-DB-005
  Scenario: An equality-filtered update with no match returns an empty list
    Given an authenticated client
    When the client updates a missing contract row
    Then the SDK operation succeeds
    And the mutation returns an empty row list
    And the existing contract row is unchanged
