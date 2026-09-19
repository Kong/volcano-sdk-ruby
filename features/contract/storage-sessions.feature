Feature: SDK upload sessions and visibility

  @storage @SDK-STORAGE-006
  Scenario: An interrupted multipart upload resumes from server progress
    Given an authenticated client
    When the client uploads one part and resumes the contract upload
    Then the SDK operation succeeds
    And upload progress describes exactly the first uploaded part
    And the completed multipart object preserves its path, type, and bytes

  @storage @SDK-STORAGE-007
  Scenario: Aborting a partial upload removes its session without publishing an object
    Given an authenticated client
    When the client uploads one part and aborts the contract upload
    Then the SDK operation succeeds
    And the aborted session and unfinished object are not found

  @storage @SDK-STORAGE-008
  Scenario: Object visibility controls anonymous reads
    Given an authenticated client
    When the client makes the contract object public and private again
    Then the SDK operation succeeds
    And anonymous reads return the original bytes only while the object is public
