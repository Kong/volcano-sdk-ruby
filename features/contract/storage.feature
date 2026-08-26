Feature: SDK storage contract

  @storage @SDK-STORAGE-001
  Scenario: Uploaded bytes can be downloaded unchanged
    Given an authenticated client
    When the client uploads and downloads the contract object
    Then the SDK operation succeeds
    And the downloaded bytes equal the uploaded bytes
