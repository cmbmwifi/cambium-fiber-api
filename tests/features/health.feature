# pub/tests/features/health.feature
@health
Feature: Health and Metrics Endpoints
  As a system administrator
  I want to verify health and monitoring endpoints
  So that I can monitor the API service availability

  Background:
    Given the API is running

  Scenario: API service is running and healthy
    When I request the health endpoint
    Then the response status code should be 200
    And the response should contain status "ok"

  Scenario: System health metrics are available for monitoring
    When I request the metrics endpoint
    Then the response status code should be 200
    And the response should be in Prometheus exposition format
    And the metrics should include "http_requests_total"
    And the metrics should include "http_request_duration_seconds"
