Feature: SDK database contract

  @database @SDK-DB-001
  Scenario: Equality filters select the matching row
    Given an authenticated client
    When the client selects the contract table where "slug" equals the fixture slug
    Then the SDK operation succeeds
    And exactly the fixture row is returned
