# pub/tests/features/health.feature
Feature: Health and Metrics Endpoints
  As a system administrator
  I want to verify health and monitoring endpoints
  So that I can monitor the API service availability

  Background:
    Given the API is running

  Scenario: Health check endpoint returns OK
    When I request the health endpoint
    Then the response status code should be 200
    And the response should contain status "ok"

  Scenario: Metrics endpoint returns Prometheus format
    When I request the metrics endpoint
    Then the response status code should be 200
    And the response should be in Prometheus exposition format
    And the metrics should include "http_requests_total"
    And the metrics should include "http_request_duration_seconds"
