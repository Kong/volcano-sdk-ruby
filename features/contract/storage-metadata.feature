Feature: SDK storage metadata contract

  @storage @SDK-STORAGE-002
  Scenario: An explicit upload content type is preserved in stored metadata
    Given an authenticated client
    When the client uploads the contract object as text/plain and reads its stored metadata
    Then the SDK operation succeeds
    And the uploaded and listed object content types are text/plain
    And the downloaded bytes equal the uploaded bytes
    And the stored object path equals the contract path
