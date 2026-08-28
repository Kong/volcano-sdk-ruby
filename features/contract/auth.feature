Feature: SDK authentication contract

  @auth @SDK-AUTH-001
  Scenario: Successful password sign-in creates a usable session
    Given the confirmed contract user
    When the client signs in with the contract user's credentials
    Then the SDK operation succeeds
    And the current session belongs to the contract user
    And the current session exposes access and refresh tokens

  @auth @SDK-AUTH-002
  Scenario: Password sign-up acknowledges a session-less account
    Given a unique unconfirmed contract user
    When the client signs up with the new user's credentials
    Then the SDK operation succeeds
    And sign-up is acknowledged without a session
    And the current session is empty

  @auth @SDK-AUTH-003
  Scenario: The current user can be retrieved and updated
    Given the client is signed in as the confirmed contract user
    When the client retrieves the current user
    Then the current user belongs to the contract user
    When the client updates the current user's metadata
    Then the current user contains the updated metadata

  @auth @SDK-AUTH-004
  Scenario: Refresh rotates tokens and failed refresh clears authentication
    Given the client is signed in as the confirmed contract user
    When the client refreshes the current session
    Then the current session exposes rotated access and refresh tokens
    When the client refreshes with an invalid refresh token
    Then the SDK operation fails
    And the current session is empty

  @auth @SDK-AUTH-005
  Scenario: Sign-out clears local authentication
    Given the client is signed in as the confirmed contract user
    When the client signs out
    Then the SDK operation succeeds
    And the current session is empty

  @auth @SDK-AUTH-006
  Scenario: Auth-state listeners observe changes until unsubscribe
    Given the client is signed in as the confirmed contract user
    When the client subscribes to auth-state changes
    Then the listener immediately observes the current user
    When the client signs out
    Then the listener observes the signed-out state
    When the client unsubscribes from auth-state changes
    And the client signs in with the contract user's credentials
    Then the listener receives no additional events

  @auth @SDK-AUTH-007
  Scenario: An anonymous user can convert to a credentialed account
    Given a unique anonymous contract user
    When the client signs up anonymously
    Then the current session belongs to the anonymous user
    When the client converts the anonymous user with credentials
    Then the SDK operation succeeds
    And the converted user keeps the anonymous user identity

  @auth @SDK-AUTH-011
  Scenario: A user can inspect and delete their sessions
    Given the client is signed in as the confirmed contract user on multiple sessions
    When the client lists the current user's sessions
    Then the session list contains the current session
    When the client deletes another current-user session
    Then the deleted session is absent from the session list
    When the client deletes all current-user sessions
    Then the current session is empty
