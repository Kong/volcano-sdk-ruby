Feature: SDK profile authentication recovery

  @auth @SDK-AUTH-007
  Scenario: A rejected profile read refreshes the session and caches the same user
    Given an authenticated client
    And the client replaces its access token with a rejected token
    When the client loads its server-validated profile
    Then the SDK operation succeeds
    And the returned and cached profiles belong to the contract user
    And the profile read replaces the rejected token for the same user
