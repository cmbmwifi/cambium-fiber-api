# pub/tests/features/profiles.feature
Feature: ONU Profile Management
  As an API client
  I want to manage ONU profiles
  So that I can configure ONU bandwidth and settings

  Background:
    Given I have a valid OAuth access token
    And at least one OLT is configured

  Scenario: List profiles for an OLT
    When I get a random OLT ID from the list
    And I request the profiles for that OLT
    Then the response status code should be 200
    And the response should be a JSON array
    And each profile should have a "profile_id" field
    And each profile should have a "profile_name" field

  Scenario: Get specific profile by ID
    When I get a random OLT ID with profiles
    And I get a random profile ID from that OLT
    And I request that specific profile
    Then the response status code should be 200
    And the response should contain the profile ID
    And the response should have a "profile_name" field

  Scenario: Update profile with dry-run mode
    When I get a random OLT ID with profiles
    And I get a random profile ID from that OLT
    And I update that profile with name "Test Profile" in dry-run mode
    Then the response status code should be 200
    And the response should contain "dry_run" as true
    And the response should contain "would_execute"

  Scenario: Create profile with dry-run mode
    When I get a random OLT ID from the list
    And I create a new profile with name "New Profile" in dry-run mode
    Then the response status code should be 200
    And the response should contain "dry_run" as true
    And the response should contain "would_execute"

  Scenario: Delete profile with dry-run mode
    When I get a random OLT ID with profiles
    And I get a random profile ID from that OLT
    And I delete that profile in dry-run mode
    Then the response status code should be 200
    And the response should contain "dry_run" as true

  Scenario: Non-existent profile returns 404
    When I get a random OLT ID from the list
    And I request profile with ID 99999 from that OLT
    Then the response status code should be 404
