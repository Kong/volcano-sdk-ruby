Feature: SDK function authentication recovery

  @functions @SDK-FUNCTIONS-002
  Scenario: A rejected user credential refreshes before function dispatch
    Given an authenticated client
    And the client replaces its access token with a rejected token
    When the authenticated client invokes the contract function by name
    Then the SDK operation succeeds
    And the function echoes the payload
    And the function invocation replaces the rejected token for the same user
