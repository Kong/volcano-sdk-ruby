Feature: SDK storage authentication recovery

  @storage @SDK-STORAGE-005
  Scenario: A rejected upload refreshes the session and preserves its bytes
    Given an authenticated client
    And the client replaces its access token with a rejected token
    When the client uploads and downloads the contract object
    Then the SDK operation succeeds
    And the downloaded bytes equal the uploaded bytes
    And the stored object path equals the contract path
    And the storage operation replaces the rejected token for the same user
