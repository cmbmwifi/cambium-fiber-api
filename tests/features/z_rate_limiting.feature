# pub/tests/features/z_rate_limiting.feature
#
# IMPORTANT: This file is prefixed with 'z_' to ensure it runs LAST in the test suite.
# The brute force test makes 11 rapid OAuth requests, exceeding the rate limit and
# blocking localhost for 10 seconds. Running it last prevents it from breaking other tests.

@auth
Feature: Rate Limiting Protection
  As a system administrator
  I want the API to protect against brute force attacks
  So that the system remains secure and available

  Scenario: Login is protected from brute force attacks
    Given I have valid OAuth credentials
    When I request an access token 11 times rapidly
    Then at least one response status code should be 429
