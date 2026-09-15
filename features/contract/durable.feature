Feature: SDK durable execution contract

  @durable @SDK-DURABLE-001
  Scenario: Starting a durable execution returns a handle, not a result
    Given a service-role client
    When the client starts the contract durable function
    Then the SDK operation succeeds
    And the started execution carries its id, function, name, region, and creation time
    And the started execution is not terminal and carries no result

  @durable @SDK-DURABLE-002
  Scenario: One execution name starts one execution
    Given a service-role client
    When the client starts the contract durable function twice under one execution name
    Then the SDK operation succeeds
    And both starts return the same execution

  @durable @SDK-DURABLE-003
  Scenario: An owner-scoped read follows an execution to its result
    Given a service-role client
    And a project-owner client
    When the client starts the contract durable function
    And the owner reads the execution until it is terminal
    Then the SDK operation succeeds
    And the execution succeeded carrying the function's result

  @durable @SDK-DURABLE-004
  Scenario: An owner-scoped list includes the started execution
    Given a service-role client
    And a project-owner client
    When the client starts the contract durable function
    And the owner lists the durable function's executions
    Then the SDK operation succeeds
    And the listed executions include the started execution
