Feature: SDK authentication contract

  @auth @SDK-AUTH-001
  Scenario: Successful password sign-in creates a usable session
    Given the confirmed contract user
    When the client signs in with the contract user's credentials
    Then the SDK operation succeeds
    And the current session belongs to the contract user
    And the current session exposes access and refresh tokens
