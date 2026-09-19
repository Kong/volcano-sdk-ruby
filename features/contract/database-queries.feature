Feature: SDK database query semantics

  @database @SDK-DB-008
  Scenario: Projected member rows use ordered pagination
    Given an authenticated client
    When the client selects a projected page of query fixture members
    Then the SDK operation succeeds
    And the projected page contains only beta and gamma in that order

  @database @SDK-DB-009
  Scenario: Numeric comparison filters preserve strict and inclusive boundaries
    Given an authenticated client
    When the client selects query fixture rows with each comparison filter
    Then the SDK operation succeeds
    And each comparison returns exactly the matching query fixture rows

  @database @SDK-DB-010
  Scenario: Pattern filters distinguish case sensitivity
    Given an authenticated client
    When the client selects query fixture rows with case-sensitive and insensitive patterns
    Then the SDK operation succeeds
    And each pattern returns exactly the matching query fixture rows

  @database @SDK-DB-011
  Scenario: Identity filters preserve null and boolean values
    Given an authenticated client
    When the client selects query fixture rows with null and boolean filters
    Then the SDK operation succeeds
    And each identity filter returns exactly the matching query fixture rows
