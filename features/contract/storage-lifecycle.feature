Feature: SDK storage lifecycle contract

  @storage @SDK-STORAGE-004
  Scenario: Copy preserves the source and move and remove affect only their target
    Given an authenticated client
    When the client copies, moves, and removes a copy of the contract object
    Then the SDK operation succeeds
    And the original, copied, and moved bytes equal the uploaded bytes
    And moving the copy leaves only the original and moved paths
    And removing the moved object leaves the original unchanged
