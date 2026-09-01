Feature: SDK authentication contract

  @auth @SDK-AUTH-001
  Scenario: Successful password sign-in creates a usable session
    Given the confirmed contract user
    When the client signs in with the contract user's credentials
    Then the SDK operation succeeds
    And the current session belongs to the contract user
    And the current session exposes access and refresh tokens

  @auth @SDK-AUTH-002
  Scenario: The auth facade returns the current session
    Given the confirmed contract user
    When the client signs in with the contract user's credentials
    And the client reads the current session
    Then the SDK operation succeeds
    And the current session belongs to the contract user
    And the current session exposes access and refresh tokens

  @auth @SDK-AUTH-003
  Scenario: A client adopts a supplied session locally
    Given the confirmed contract user
    When the client signs in with the contract user's credentials
    And a fresh client adopts the current session
    Then the SDK operation succeeds
    And the current session belongs to the contract user
    And the current session exposes access and refresh tokens

  @auth @SDK-AUTH-004
  Scenario: A client refreshes its current session
    Given the confirmed contract user
    When the client signs in with the contract user's credentials
    And the client refreshes the current session
    Then the SDK operation succeeds
    And the refreshed session becomes current
    And the current session belongs to the contract user
    And the current session exposes access and refresh tokens

  @auth @SDK-AUTH-005
  Scenario: A client signs out its current session
    Given the confirmed contract user
    When the client signs in with the contract user's credentials
    And the client signs out
    Then the SDK operation succeeds
    And the current session is empty
    When a fresh client tries to refresh the signed-out session
    Then the SDK operation fails with an authentication error
    And the current session is empty

  @auth @SDK-AUTH-006
  Scenario: An auth-state listener observes sign-in
    Given the confirmed contract user
    And the client listens for auth state changes
    When the client signs in with the contract user's credentials
    Then the SDK operation succeeds
    And the auth-state listener observes the signed-in contract user
