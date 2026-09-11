Feature: SDK storage range contract

  @storage @SDK-STORAGE-003
  Scenario: A byte range download returns exactly the requested bytes
    Given an authenticated client
    When the client uploads the contract object and downloads bytes 2 through 7
    Then the SDK operation succeeds
    And the downloaded bytes equal uploaded bytes 2 through 7 inclusive
    And the stored object path equals the contract path
