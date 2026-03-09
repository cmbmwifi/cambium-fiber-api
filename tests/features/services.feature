# pub/tests/features/services.feature
@services
Feature: Service Profile Management
  As an API client
  I want to manage service profiles (VLAN/port configurations)
  So that I can configure network services for ONUs

  Background:
    Given I have a valid OAuth access token
    And at least one OLT is configured

  Scenario: Service profiles can be listed for an OLT
    When I get a random OLT ID from the list
    And I request the service profiles for that OLT
    Then the response status code should be 200
    And the response should be a JSON array

  Scenario: Individual service profile can be retrieved
    When I get a random OLT ID with service profiles
    And I get a random service profile ID from that OLT
    And I request that specific service profile
    Then the response status code should be 200
    And the response should contain the service profile ID

  Scenario: Service profile changes can be safely previewed before applying
    When I get a random OLT ID with service profiles
    And I get a random service profile ID from that OLT
    And I update that service profile with dry-run mode
    Then the response status code should be 200
    And the response should contain "dry_run" as true
    And the response should have an "would_execute" field

  Scenario: Missing service profile is reported correctly
    When I get a random OLT ID from the list
    And I request service profile with ID 99999 from that OLT
    Then the response status code should be 404
