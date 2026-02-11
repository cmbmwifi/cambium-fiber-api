# pub/tests/features/authentication.feature
Feature: OAuth Authentication
  As an API client
  I want to authenticate using OAuth 2.0 Client Credentials flow
  So that I can securely access the API

  Scenario: Successfully obtain OAuth access token
    Given I have valid OAuth credentials
    When I request an access token
    Then the response status code should be 200
    And the response should contain an "access_token"
    And the response should contain "token_type" as "Bearer"
    And the response should contain "expires_in"

  Scenario: Invalid credentials are rejected
    Given I have invalid OAuth credentials
    When I request an access token
    Then the response status code should be 401
    And the response should contain an error message

  Scenario: Access token can be used for authenticated requests
    Given I have a valid OAuth access token
    When I make an authenticated request to "/api/v2/fiber/olts"
    Then the response status code should be 200

  Scenario: Requests without token are rejected
    When I make an unauthenticated request to "/api/v2/fiber/olts"
    Then the response status code should be 401

  Scenario: Rate limiting protects token endpoint
    Given I have valid OAuth credentials
    When I request an access token 15 times rapidly
    Then at least one response status code should be 429
    And the rate limit headers should be present
