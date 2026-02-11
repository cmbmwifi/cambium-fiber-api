# pub/tests/features/services.feature
Feature: Service Profile Management
  As an API client
  I want to manage service profiles (VLAN/port configurations)
  So that I can configure network services for ONUs

  Background:
    Given I have a valid OAuth access token
    And at least one OLT is configured

  Scenario: List service profiles for an OLT
    When I get a random OLT ID from the list
    And I request the service profiles for that OLT
    Then the response status code should be 200
    And the response should be a JSON array

  Scenario: Get specific service profile by ID
    When I get a random OLT ID with service profiles
    And I get a random service profile ID from that OLT
    And I request that specific service profile
    Then the response status code should be 200
    And the response should contain the service profile ID

  Scenario: Update service profile with dry-run mode
    When I get a random OLT ID with service profiles
    And I get a random service profile ID from that OLT
    And I update that service profile with dry-run mode
    Then the response status code should be 200
    And the response should contain "dry_run" as true
    And the response should contain "would_execute"

  Scenario: Create service profile with dry-run mode
    When I get a random OLT ID from the list
    And I create a new service profile in dry-run mode
    Then the response status code should be 200
    And the response should contain "dry_run" as true
    And the response should contain "would_execute"

  Scenario: Delete service profile with dry-run mode
    When I get a random OLT ID with service profiles
    And I get a random service profile ID from that OLT
    And I delete that service profile in dry-run mode
    Then the response status code should be 200
    And the response should contain "dry_run" as true

  Scenario: Non-existent service profile returns 404
    When I get a random OLT ID from the list
    And I request service profile with ID 99999 from that OLT
    Then the response status code should be 404
