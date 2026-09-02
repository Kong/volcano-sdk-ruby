Feature: SDK database update contract

  @database @SDK-DB-003
  Scenario: An equality-filtered update returns the changed row
    Given an authenticated client
    When the client updates its contract row
    Then the SDK operation succeeds
    And exactly the updated contract row is returned
