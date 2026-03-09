# pub/tests/features/authentication.feature
@auth
Feature: OAuth Authentication
  As an API client
  I want to authenticate using OAuth 2.0 Client Credentials flow
  So that I can securely access the API

  Scenario: Login succeeds with valid credentials
    Given I have valid OAuth credentials
    When I request an access token
    Then the response status code should be 200
    And the response should contain an "access_token"
    And the response should contain an "token_type"
    And the response should contain an "expires_in"

  Scenario: Invalid credentials are properly rejected
    Given I have invalid OAuth credentials
    When I request an access token
    Then the response status code should be 401
    And the response should contain an error message

  Scenario: Authenticated requests are accepted
    Given I have a valid OAuth access token
    When I make an authenticated request to "/api/v2/fiber/olts"
    Then the response status code should be 200

  Scenario: Unauthenticated requests are properly handled
    When I make an unauthenticated request to "/api/v2/fiber/olts"
    Then the response should indicate authentication is required
