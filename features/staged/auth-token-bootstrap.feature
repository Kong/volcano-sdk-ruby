Feature: SDK token-only authentication

  @auth @SDK-AUTH-008
  Scenario: A client uses a supplied access token without inventing session fields
    Given an authenticated client
    When a fresh client starts with only the current access token
    Then the SDK operation succeeds
    And the token-only session has no cached user
    And the session retains only the supplied access token
    When the client loads its server-validated profile
    Then the SDK operation succeeds
    And the returned and cached profiles belong to the contract user
    And the session retains only the supplied access token
    When the client signs out
    Then the SDK operation succeeds
    And the current session is empty
