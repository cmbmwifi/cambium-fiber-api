# pub/tests/features/onus_read.feature
@onus
Feature: ONU Read Operations
  As an API client
  I want to retrieve ONU information
  So that I can monitor and manage ONUs

  Background:
    Given I have a valid OAuth access token
    And at least one OLT is configured

  Scenario: All ONUs can be listed across all OLTs
    When I request the list of all ONUs
    Then the response status code should be 200
    And the response should be a JSON array
    And each ONU should have a "serial" field

  Scenario: ONU list supports paging through results
    When I request the list of ONUs with page 1 and 5 items per page
    Then the response status code should be 200
    And the response should contain at most 5 ONUs
    And the response headers should include Link headers

  Scenario: ONUs can be filtered by connection status
    When I request the list of ONUs filtered by status "online"
    Then the response status code should be 200
    And the response should be a JSON array
    And all returned ONUs should have status "online" if any exist

  Scenario: Individual ONU can be looked up by serial number
    When I get a random ONU serial from the list
    And I request the ONU details by serial
    Then the response status code should be 200
    And the response should contain the ONU serial
    And the response should have an "name" field

  Scenario: ONUs can be listed for a specific OLT
    When I get a random OLT ID from the list
    And I request the ONUs for that OLT
    Then the response status code should be 200
    And the response should be a JSON array
    And each ONU should have a "serial" field

  Scenario: Individual ONU can be retrieved from a specific OLT
    When I get a random OLT ID from the list
    And I get a random ONU from that OLT
    And I request the ONU from that specific OLT
    Then the response status code should be 200
    And the response should contain the ONU serial

  Scenario: Missing ONU is reported correctly
    When I request an ONU with serial "NOTFOUND123456"
    Then the response status code should be 404
