Feature: SDK authenticated request recovery

  @auth @SDK-AUTH-009
  Scenario: A rejected session list refreshes the captured session once
    Given an authenticated client
    And the client replaces its access token with a rejected token
    When the client lists its server sessions
    Then the SDK operation succeeds
    And the session list contains the current session for the contract user
    And the session list replaces the rejected token for the same user
