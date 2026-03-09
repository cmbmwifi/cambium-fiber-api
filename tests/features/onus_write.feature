# pub/tests/features/onus_write.feature
@onus
Feature: ONU Write Operations (Dry-Run Mode)
  As an API client
  I want to test ONU write operations in dry-run mode
  So that I can validate changes without modifying the OLT

  Background:
    Given I have a valid OAuth access token
    And at least one ONU exists

  Scenario: ONU changes can be safely previewed before applying
    When I get a random ONU serial from the list
    And I update that ONU with name "Test Customer" in dry-run mode
    Then the response status code should be 200
    And the response should contain "dry_run" as true
    And the response should have an "would_execute" field
    And the response should contain "validation" as "passed"

  Scenario: ONU changes can be safely previewed on a specific OLT
    When I get a random OLT ID with ONUs
    And I get a random ONU from that OLT
    And I update that ONU on that OLT with name "Test Customer" in dry-run mode
    Then the response status code should be 200
    And the response should contain "dry_run" as true
    And the response should have an "would_execute" field

  Scenario: Multiple ONU changes can be safely previewed at once
    When I get up to 3 ONU serials from the list
    And I bulk update those ONUs with admin_status "disabled" in dry-run mode
    Then the response status code should be 200
    And the response should contain "dry_run" as true
    And the response should have an "would_execute" field

  Scenario: Invalid ONU changes are rejected
    When I attempt to update a non-existent ONU in dry-run mode
    Then the response status code should be 404

  Scenario: Invalid data is caught before changes are applied
    When I get a random ONU serial from the list
    And I attempt to update that ONU with invalid data in dry-run mode
    Then the response status code should be 200
    And the response should contain "dry_run" as true
