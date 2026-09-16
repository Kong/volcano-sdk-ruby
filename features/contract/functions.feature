Feature: SDK function invocation contract

  @functions @SDK-FUNCTIONS-001
  Scenario: A function invoked by name answers from the resolved endpoint
    Given a service-role client
    When the client invokes the contract function by name
    Then the SDK operation succeeds
    And the function echoes the payload
