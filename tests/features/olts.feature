# pub/tests/features/olts.feature
@olts
Feature: OLT Management
  As an API client
  I want to list available OLTs
  So that I can discover which OLTs are configured

  Background:
    Given I have a valid OAuth access token

  Scenario: All configured OLTs can be listed
    When I request the list of OLTs
    Then the response status code should be 200
    And the response should be a JSON array
    And the response should contain at least one OLT ID
    And each OLT ID should be a string

  Scenario: OLT data is compatible with cnMaestro
    When I request the list of OLTs
    Then the response should be a direct array
    And the response should not have a wrapper object
