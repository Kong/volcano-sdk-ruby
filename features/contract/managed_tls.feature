Feature: Managed custom-domain TLS contract

  @managed-tls @TLS-MANAGED-001
  Scenario: Managed TLS uses an explicit secret-free request and DNS lifecycle response
    Given a managed custom-domain TLS request
    When the client encodes the request and decodes a pending verification response
    Then the request selects managed TLS without certificate material
    And the response exposes the managed lifecycle and DNS records
