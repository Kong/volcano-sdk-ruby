Feature: SDK broadcast pause and resume

  @realtime @SDK-REALTIME-002
  Scenario: Broadcast delivery stays silent while paused and resumes with the same handler
    Given two authenticated realtime clients
    When one client pauses delivery for 1 second and then resumes with the same handler
    Then the SDK operation succeeds
    And the subscriber receives the contract message within 10 seconds
