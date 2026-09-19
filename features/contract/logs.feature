Feature: SDK retained project log contract

  @logs @SDK-LOGS-001
  Scenario: A project token searches and paginates structured function logs
    Given a read-only project logs client
    When the contract function emits three unique structured log events
    And the client searches and paginates those events within 240 seconds
    Then the SDK operation succeeds
    And all three structured events retain their metadata without duplicates

  @logs @SDK-LOGS-002
  Scenario: A project token counts a matching function log in activity buckets
    Given a read-only project logs client
    When the contract function emits one unique structured log event
    And the client reads matching log activity within 120 seconds
    Then the SDK operation succeeds
    And activity counts exactly that event in its function and level buckets
