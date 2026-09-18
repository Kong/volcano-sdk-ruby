Feature: SDK lock recovery and lifecycle

  @locks @SDK-LOCKS-002
  Scenario: Caller-owned acquisition can be recovered and renewed
    Given a service-role client
    When the client recovers the contract lock with caller-owned tokens
    Then the SDK operation succeeds
    And recovery and renewal preserve the held lease until release

  @locks @SDK-LOCKS-003
  Scenario: Administrative release removes the current lease
    Given a service-role client
    When the client acquires and force releases the contract lock
    Then the SDK operation succeeds
    And the force-released lock is available
    When the client reacquires the force-released contract lock
    Then the SDK operation succeeds
    And the replacement owner receives a higher fencing token
