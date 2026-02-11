# pub/tests/features/olts.feature
Feature: OLT Management
  As an API client
  I want to list available OLTs
  So that I can discover which OLTs are configured

  Background:
    Given I have a valid OAuth access token

  Scenario: List all OLT IDs
    When I request the list of OLTs
    Then the response status code should be 200
    And the response should be a JSON array
    And the response should contain at least one OLT ID
    And each OLT ID should be a string

  Scenario: OLT list follows cnMaestro array pattern
    When I request the list of OLTs
    Then the response should be a direct array
    And the response should not have a wrapper object
