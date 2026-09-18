Feature: SDK token-only authentication

  @auth @SDK-AUTH-008
  Scenario: A client uses a supplied access token without inventing session fields
    Given an authenticated client
    When a fresh client tries to refresh a supplied profile without a session identifier
    Then the SDK operation fails
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
    When a fresh client loads a profile with the signed-out access token
    Then the SDK operation fails with an authentication error
    When a fresh client starts with a rejected access token
    And the client loads its server-validated profile
    Then the SDK operation fails with an authentication error
    And the session retains only the supplied access token
    And the token-only session has no cached user
    When the client refreshes the current session
    Then the SDK operation fails
    And the session retains only the supplied access token
    When the client signs out
    Then the SDK operation succeeds
    And the current session is empty
