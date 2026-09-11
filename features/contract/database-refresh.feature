Feature: SDK database authentication recovery

  @database @SDK-DB-007
  Scenario: A rejected database read refreshes the session and retries
    Given an authenticated client
    And the client replaces its access token with a rejected token
    When the client selects the contract table where "slug" equals the fixture slug
    Then the SDK operation succeeds
    And exactly the fixture row is returned
    And the database read replaces the rejected token for the same user
