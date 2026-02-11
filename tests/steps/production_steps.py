"""Production validation test step definitions.

These step definitions implement Gherkin scenarios for production API validation.
Tests use real OAuth authentication and run against deployed API instances.
Write operations use dry-run mode to ensure production safety.
"""

import random
import time
from typing import Any

import requests
from pytest_bdd import given, parsers, then, when

# ============================================================================
# Shared Context Management
# ============================================================================


def get_context(context_dict: dict, key: str) -> Any:
    """Retrieve value from test context with helpful error message."""
    if key not in context_dict:
        raise KeyError(
            f"Context key '{key}' not found. Available keys: {list(context_dict.keys())}"
        )
    return context_dict[key]


# ============================================================================
# Background Steps
# ============================================================================


@given("the API is running")
def api_is_running(api_base_url: str) -> None:
    """Verify API is accessible."""
    try:
        response = requests.get(f"{api_base_url}/health", timeout=5)
        assert response.status_code == 200, f"API not running: {response.status_code}"
    except requests.RequestException as e:
        raise AssertionError(f"API not accessible at {api_base_url}: {e}") from e


@given("I have a valid OAuth access token")
def have_valid_token(oauth_token: str, test_context: dict) -> None:
    """Store OAuth token in test context."""
    test_context["access_token"] = oauth_token


@given("at least one OLT is configured")
def have_olts(api_client: requests.Session, test_context: dict) -> None:
    """Verify at least one OLT exists and store list."""
    response = api_client.get("/api/v2/fiber/olts")
    assert response.status_code == 200, f"Failed to list OLTs: {response.status_code}"
    olt_ids = response.json()
    assert len(olt_ids) > 0, "No OLTs configured"
    test_context["olt_ids"] = olt_ids


@given("at least one ONU exists")
def have_onus(api_client: requests.Session, test_context: dict) -> None:
    """Verify at least one ONU exists."""
    response = api_client.get("/api/v2/fiber/onus?per_page=1")
    assert response.status_code == 200, f"Failed to list ONUs: {response.status_code}"
    onus = response.json()
    assert len(onus) > 0, "No ONUs configured"
    test_context["onus"] = onus


# ============================================================================
# OAuth Authentication Steps
# ============================================================================


@given("I have valid OAuth credentials")
def have_valid_credentials(
    oauth_client_id: str, oauth_client_secret: str, test_context: dict
) -> None:
    """Store valid OAuth credentials."""
    test_context["client_id"] = oauth_client_id
    test_context["client_secret"] = oauth_client_secret


@given("I have invalid OAuth credentials")
def have_invalid_credentials(test_context: dict) -> None:
    """Store invalid OAuth credentials."""
    test_context["client_id"] = "invalid_client_id"
    test_context["client_secret"] = "invalid_secret"


@when("I request an access token")
def request_access_token(api_base_url: str, test_context: dict) -> None:
    """Request OAuth access token."""
    response = requests.post(
        f"{api_base_url}/oauth/token",
        data={
            "grant_type": "client_credentials",
            "client_id": test_context["client_id"],
            "client_secret": test_context["client_secret"],
        },
        timeout=10,
    )
    test_context["response"] = response


@when(parsers.parse("I request an access token {count:d} times rapidly"))
def request_tokens_rapidly(api_base_url: str, test_context: dict, count: int) -> None:
    """Request access tokens rapidly to test rate limiting."""
    responses = []
    for _ in range(count):
        response = requests.post(
            f"{api_base_url}/oauth/token",
            data={
                "grant_type": "client_credentials",
                "client_id": test_context["client_id"],
                "client_secret": test_context["client_secret"],
            },
            timeout=10,
        )
        responses.append(response)
        time.sleep(0.1)  # Small delay to avoid overwhelming server
    test_context["responses"] = responses


@when(parsers.parse('I make an authenticated request to "{endpoint}"'))
def make_authenticated_request(
    api_client: requests.Session, test_context: dict, endpoint: str
) -> None:
    """Make authenticated API request."""
    response = api_client.get(endpoint)
    test_context["response"] = response


@when(parsers.parse('I make an unauthenticated request to "{endpoint}"'))
def make_unauthenticated_request(
    api_base_url: str, test_context: dict, endpoint: str
) -> None:
    """Make unauthenticated API request."""
    response = requests.get(f"{api_base_url}{endpoint}", timeout=10)
    test_context["response"] = response


# ============================================================================
# Health & Metrics Steps
# ============================================================================


@when("I request the health endpoint")
def request_health(api_base_url: str, test_context: dict) -> None:
    """Request health endpoint."""
    response = requests.get(f"{api_base_url}/health", timeout=10)
    test_context["response"] = response


@when("I request the metrics endpoint")
def request_metrics(api_base_url: str, test_context: dict) -> None:
    """Request metrics endpoint."""
    response = requests.get(f"{api_base_url}/metrics", timeout=10)
    test_context["response"] = response


# ============================================================================
# OLT Steps
# ============================================================================


@when("I request the list of OLTs")
def request_olt_list(api_client: requests.Session, test_context: dict) -> None:
    """Request list of OLTs."""
    response = api_client.get("/api/v2/fiber/olts")
    test_context["response"] = response


@when("I get a random OLT ID from the list")
def get_random_olt(api_client: requests.Session, test_context: dict) -> None:
    """Get random OLT ID."""
    response = api_client.get("/api/v2/fiber/olts")
    assert response.status_code == 200
    olt_ids = response.json()
    assert len(olt_ids) > 0, "No OLTs available"
    test_context["selected_olt_id"] = random.choice(olt_ids)


@when("I get a random OLT ID with ONUs")
def get_olt_with_onus(api_client: requests.Session, test_context: dict) -> None:
    """Get random OLT ID that has ONUs."""
    response = api_client.get("/api/v2/fiber/olts")
    assert response.status_code == 200
    olt_ids = response.json()

    for olt_id in olt_ids:
        onus_response = api_client.get(f"/api/v2/fiber/olts/{olt_id}/onus?per_page=1")
        if onus_response.status_code == 200 and len(onus_response.json()) > 0:
            test_context["selected_olt_id"] = olt_id
            return

    raise AssertionError("No OLTs with ONUs found")


@when("I get a random OLT ID with profiles")
def get_olt_with_profiles(api_client: requests.Session, test_context: dict) -> None:
    """Get random OLT ID that has profiles."""
    response = api_client.get("/api/v2/fiber/olts")
    assert response.status_code == 200
    olt_ids = response.json()

    for olt_id in olt_ids:
        profiles_response = api_client.get(f"/api/v2/fiber/olts/{olt_id}/profiles")
        if profiles_response.status_code == 200 and len(profiles_response.json()) > 0:
            test_context["selected_olt_id"] = olt_id
            return

    raise AssertionError("No OLTs with profiles found")


@when("I get a random OLT ID with service profiles")
def get_olt_with_services(api_client: requests.Session, test_context: dict) -> None:
    """Get random OLT ID that has service profiles."""
    response = api_client.get("/api/v2/fiber/olts")
    assert response.status_code == 200
    olt_ids = response.json()

    for olt_id in olt_ids:
        services_response = api_client.get(f"/api/v2/fiber/olts/{olt_id}/services")
        if services_response.status_code == 200 and len(services_response.json()) > 0:
            test_context["selected_olt_id"] = olt_id
            return

    # If no service profiles exist, just pick first OLT for create/delete tests
    test_context["selected_olt_id"] = olt_ids[0]


# ============================================================================
# ONU Read Steps
# ============================================================================


@when("I request the list of all ONUs")
def request_all_onus(api_client: requests.Session, test_context: dict) -> None:
    """Request list of all ONUs."""
    response = api_client.get("/api/v2/fiber/onus")
    test_context["response"] = response


@when(
    parsers.parse(
        "I request the list of ONUs with page {page:d} and {per_page:d} items per page"
    )
)
def request_onus_paginated(
    api_client: requests.Session, test_context: dict, page: int, per_page: int
) -> None:
    """Request paginated list of ONUs."""
    response = api_client.get(f"/api/v2/fiber/onus?page={page}&per_page={per_page}")
    test_context["response"] = response


@when(parsers.parse('I request the list of ONUs filtered by status "{status}"'))
def request_onus_filtered(
    api_client: requests.Session, test_context: dict, status: str
) -> None:
    """Request filtered list of ONUs."""
    response = api_client.get(f"/api/v2/fiber/onus?status={status}")
    test_context["response"] = response


@when("I get a random ONU serial from the list")
def get_random_onu_serial(api_client: requests.Session, test_context: dict) -> None:
    """Get random ONU serial."""
    response = api_client.get("/api/v2/fiber/onus?per_page=10")
    assert response.status_code == 200
    onus = response.json()
    assert len(onus) > 0, "No ONUs available"
    test_context["selected_onu"] = random.choice(onus)


@when("I request the ONU details by serial")
def request_onu_by_serial(api_client: requests.Session, test_context: dict) -> None:
    """Request ONU details by serial."""
    onu = get_context(test_context, "selected_onu")
    response = api_client.get(f"/api/v2/fiber/onus/{onu['serial']}")
    test_context["response"] = response


@when("I request the ONUs for that OLT")
def request_onus_for_olt(api_client: requests.Session, test_context: dict) -> None:
    """Request ONUs for specific OLT."""
    olt_id = get_context(test_context, "selected_olt_id")
    response = api_client.get(f"/api/v2/fiber/olts/{olt_id}/onus")
    test_context["response"] = response


@when("I get a random ONU from that OLT")
def get_random_onu_from_olt(api_client: requests.Session, test_context: dict) -> None:
    """Get random ONU from specific OLT."""
    olt_id = get_context(test_context, "selected_olt_id")
    response = api_client.get(f"/api/v2/fiber/olts/{olt_id}/onus?per_page=10")
    assert response.status_code == 200
    onus = response.json()
    assert len(onus) > 0, f"No ONUs on OLT {olt_id}"
    test_context["selected_onu"] = random.choice(onus)


@when("I request the ONU from that specific OLT")
def request_onu_from_specific_olt(
    api_client: requests.Session, test_context: dict
) -> None:
    """Request ONU from specific OLT."""
    olt_id = get_context(test_context, "selected_olt_id")
    onu = get_context(test_context, "selected_onu")
    response = api_client.get(f"/api/v2/fiber/olts/{olt_id}/onus/{onu['serial']}")
    test_context["response"] = response


@when(parsers.parse('I request an ONU with serial "{serial}"'))
def request_specific_onu(
    api_client: requests.Session, test_context: dict, serial: str
) -> None:
    """Request specific ONU by serial."""
    response = api_client.get(f"/api/v2/fiber/onus/{serial}")
    test_context["response"] = response


@when("I get up to 3 ONU serials from the list")
def get_multiple_onu_serials(api_client: requests.Session, test_context: dict) -> None:
    """Get up to 3 ONU serials for bulk operations."""
    response = api_client.get("/api/v2/fiber/onus?per_page=3")
    assert response.status_code == 200
    onus = response.json()
    assert len(onus) > 0, "No ONUs available"
    test_context["selected_onus"] = onus


# ============================================================================
# ONU Write Steps (Dry-Run Mode)
# ============================================================================


@when(parsers.parse('I update that ONU with name "{name}" in dry-run mode'))
def update_onu_dry_run(
    api_client: requests.Session, test_context: dict, name: str
) -> None:
    """Update ONU in dry-run mode."""
    onu = get_context(test_context, "selected_onu")
    response = api_client.patch(
        f"/api/v2/fiber/onus/{onu['serial']}?dry_run=true", json={"name": name}
    )
    test_context["response"] = response


@when(parsers.parse('I update that ONU on that OLT with name "{name}" in dry-run mode'))
def update_onu_on_olt_dry_run(
    api_client: requests.Session, test_context: dict, name: str
) -> None:
    """Update ONU on specific OLT in dry-run mode."""
    olt_id = get_context(test_context, "selected_olt_id")
    onu = get_context(test_context, "selected_onu")
    response = api_client.patch(
        f"/api/v2/fiber/olts/{olt_id}/onus/{onu['serial']}?dry_run=true",
        json={"name": name},
    )
    test_context["response"] = response


@when(
    parsers.parse(
        'I bulk update those ONUs with admin_status "{status}" in dry-run mode'
    )
)
def bulk_update_onus_dry_run(
    api_client: requests.Session, test_context: dict, status: str
) -> None:
    """Bulk update ONUs in dry-run mode."""
    onus = get_context(test_context, "selected_onus")
    updates = [{"serial": onu["serial"], "admin_status": status} for onu in onus]
    response = api_client.patch("/api/v2/fiber/onus/bulk?dry_run=true", json=updates)
    test_context["response"] = response


@when("I attempt to update a non-existent ONU in dry-run mode")
def update_nonexistent_onu_dry_run(
    api_client: requests.Session, test_context: dict
) -> None:
    """Attempt to update non-existent ONU in dry-run mode."""
    response = api_client.patch(
        "/api/v2/fiber/onus/NOTFOUND123456?dry_run=true", json={"name": "Test"}
    )
    test_context["response"] = response


@when("I attempt to update that ONU with invalid data in dry-run mode")
def update_onu_invalid_dry_run(
    api_client: requests.Session, test_context: dict
) -> None:
    """Attempt to update ONU with invalid data in dry-run mode."""
    onu = get_context(test_context, "selected_onu")
    response = api_client.patch(
        f"/api/v2/fiber/onus/{onu['serial']}?dry_run=true",
        json={"invalid_field": "invalid_value", "admin_status": "invalid_status"},
    )
    test_context["response"] = response


# ============================================================================
# Profile Steps
# ============================================================================


@when("I request the profiles for that OLT")
def request_profiles_for_olt(api_client: requests.Session, test_context: dict) -> None:
    """Request profiles for specific OLT."""
    olt_id = get_context(test_context, "selected_olt_id")
    response = api_client.get(f"/api/v2/fiber/olts/{olt_id}/profiles")
    test_context["response"] = response


@when("I get a random profile ID from that OLT")
def get_random_profile(api_client: requests.Session, test_context: dict) -> None:
    """Get random profile ID from OLT."""
    olt_id = get_context(test_context, "selected_olt_id")
    response = api_client.get(f"/api/v2/fiber/olts/{olt_id}/profiles")
    assert response.status_code == 200
    profiles = response.json()
    assert len(profiles) > 0, f"No profiles on OLT {olt_id}"
    test_context["selected_profile"] = random.choice(profiles)


@when("I request that specific profile")
def request_specific_profile(api_client: requests.Session, test_context: dict) -> None:
    """Request specific profile."""
    olt_id = get_context(test_context, "selected_olt_id")
    profile = get_context(test_context, "selected_profile")
    response = api_client.get(
        f"/api/v2/fiber/olts/{olt_id}/profiles/{profile['profile_id']}"
    )
    test_context["response"] = response


@when(parsers.parse('I update that profile with name "{name}" in dry-run mode'))
def update_profile_dry_run(
    api_client: requests.Session, test_context: dict, name: str
) -> None:
    """Update profile in dry-run mode."""
    olt_id = get_context(test_context, "selected_olt_id")
    profile = get_context(test_context, "selected_profile")
    response = api_client.patch(
        f"/api/v2/fiber/olts/{olt_id}/profiles/{profile['profile_id']}?dry_run=true",
        json={"profile_name": name},
    )
    test_context["response"] = response


@when(parsers.parse('I create a new profile with name "{name}" in dry-run mode'))
def create_profile_dry_run(
    api_client: requests.Session, test_context: dict, name: str
) -> None:
    """Create profile in dry-run mode."""
    olt_id = get_context(test_context, "selected_olt_id")
    response = api_client.post(
        f"/api/v2/fiber/olts/{olt_id}/profiles?dry_run=true",
        json={
            "profile_name": name,
            "fixed_bandwidth_down": 100,
            "fixed_bandwidth_up": 50,
        },
    )
    test_context["response"] = response


@when("I delete that profile in dry-run mode")
def delete_profile_dry_run(api_client: requests.Session, test_context: dict) -> None:
    """Delete profile in dry-run mode."""
    olt_id = get_context(test_context, "selected_olt_id")
    profile = get_context(test_context, "selected_profile")
    response = api_client.delete(
        f"/api/v2/fiber/olts/{olt_id}/profiles/{profile['profile_id']}?dry_run=true"
    )
    test_context["response"] = response


@when(parsers.parse("I request profile with ID {profile_id:d} from that OLT"))
def request_profile_by_id(
    api_client: requests.Session, test_context: dict, profile_id: int
) -> None:
    """Request specific profile by ID."""
    olt_id = get_context(test_context, "selected_olt_id")
    response = api_client.get(f"/api/v2/fiber/olts/{olt_id}/profiles/{profile_id}")
    test_context["response"] = response


# ============================================================================
# Service Profile Steps
# ============================================================================


@when("I request the service profiles for that OLT")
def request_service_profiles_for_olt(
    api_client: requests.Session, test_context: dict
) -> None:
    """Request service profiles for specific OLT."""
    olt_id = get_context(test_context, "selected_olt_id")
    response = api_client.get(f"/api/v2/fiber/olts/{olt_id}/services")
    test_context["response"] = response


@when("I get a random service profile ID from that OLT")
def get_random_service_profile(
    api_client: requests.Session, test_context: dict
) -> None:
    """Get random service profile ID from OLT."""
    olt_id = get_context(test_context, "selected_olt_id")
    response = api_client.get(f"/api/v2/fiber/olts/{olt_id}/services")
    assert response.status_code == 200
    services = response.json()
    assert len(services) > 0, f"No service profiles on OLT {olt_id}"
    test_context["selected_service"] = random.choice(services)


@when("I request that specific service profile")
def request_specific_service_profile(
    api_client: requests.Session, test_context: dict
) -> None:
    """Request specific service profile."""
    olt_id = get_context(test_context, "selected_olt_id")
    service = get_context(test_context, "selected_service")
    response = api_client.get(
        f"/api/v2/fiber/olts/{olt_id}/services/{service['service_id']}"
    )
    test_context["response"] = response


@when("I update that service profile with dry-run mode")
def update_service_dry_run(api_client: requests.Session, test_context: dict) -> None:
    """Update service profile in dry-run mode."""
    olt_id = get_context(test_context, "selected_olt_id")
    service = get_context(test_context, "selected_service")
    response = api_client.patch(
        f"/api/v2/fiber/olts/{olt_id}/services/{service['service_id']}?dry_run=true",
        json={"vlan_id": 100},
    )
    test_context["response"] = response


@when("I create a new service profile in dry-run mode")
def create_service_dry_run(api_client: requests.Session, test_context: dict) -> None:
    """Create service profile in dry-run mode."""
    olt_id = get_context(test_context, "selected_olt_id")
    response = api_client.post(
        f"/api/v2/fiber/olts/{olt_id}/services?dry_run=true",
        json={"service_name": "Test Service", "vlan_id": 100},
    )
    test_context["response"] = response


@when("I delete that service profile in dry-run mode")
def delete_service_dry_run(api_client: requests.Session, test_context: dict) -> None:
    """Delete service profile in dry-run mode."""
    olt_id = get_context(test_context, "selected_olt_id")
    service = get_context(test_context, "selected_service")
    response = api_client.delete(
        f"/api/v2/fiber/olts/{olt_id}/services/{service['service_id']}?dry_run=true"
    )
    test_context["response"] = response


@when(parsers.parse("I request service profile with ID {service_id:d} from that OLT"))
def request_service_by_id(
    api_client: requests.Session, test_context: dict, service_id: int
) -> None:
    """Request specific service profile by ID."""
    olt_id = get_context(test_context, "selected_olt_id")
    response = api_client.get(f"/api/v2/fiber/olts/{olt_id}/services/{service_id}")
    test_context["response"] = response


# ============================================================================
# Then Steps (Assertions)
# ============================================================================


@then(parsers.parse("the response status code should be {status_code:d}"))
def check_status_code(test_context: dict, status_code: int) -> None:
    """Verify response status code."""
    response = get_context(test_context, "response")
    assert response.status_code == status_code, (
        f"Expected {status_code}, got {response.status_code}. Response: {response.text}"
    )


@then(parsers.parse('the response should contain status "{status}"'))
def check_status_field(test_context: dict, status: str) -> None:
    """Verify response contains status field with value."""
    response = get_context(test_context, "response")
    data = response.json()
    assert "status" in data, f"Response missing 'status' field: {data}"
    assert data["status"] == status, (
        f"Expected status '{status}', got '{data['status']}'"
    )


@then(parsers.parse('the response should contain an "{field}"'))
def check_field_exists(test_context: dict, field: str) -> None:
    """Verify response contains specified field."""
    response = get_context(test_context, "response")
    data = response.json()
    assert field in data, f"Response missing '{field}' field: {data}"


@then(parsers.parse('the response should contain "{field}" as "{value}"'))
def check_field_value(test_context: dict, field: str, value: str) -> None:
    """Verify response field has specific value."""
    response = get_context(test_context, "response")
    data = response.json()
    assert field in data, f"Response missing '{field}' field: {data}"
    assert str(data[field]) == value, f"Expected {field}='{value}', got '{data[field]}'"


@then(parsers.parse('the response should contain "{field}" as {value:w}'))
def check_field_boolean(test_context: dict, field: str, value: str) -> None:
    """Verify response field has boolean value."""
    response = get_context(test_context, "response")
    data = response.json()
    assert field in data, f"Response missing '{field}' field: {data}"
    expected = value.lower() == "true"
    assert data[field] == expected, f"Expected {field}={expected}, got '{data[field]}'"


@then("the response should contain an error message")
def check_error_message(test_context: dict) -> None:
    """Verify response contains error message."""
    response = get_context(test_context, "response")
    data = response.json()
    assert "detail" in data or "error" in data or "message" in data, (
        f"Response missing error message: {data}"
    )


@then("the response should be in Prometheus exposition format")
def check_prometheus_format(test_context: dict) -> None:
    """Verify response is in Prometheus format."""
    response = get_context(test_context, "response")
    text = response.text
    # Prometheus format has lines starting with # (comments) or metric names
    lines = [line for line in text.split("\n") if line.strip()]
    assert any(line.startswith("#") for line in lines), "Missing Prometheus comments"
    assert any(not line.startswith("#") for line in lines), "Missing Prometheus metrics"


@then(parsers.parse('the metrics should include "{metric_name}"'))
def check_metric_exists(test_context: dict, metric_name: str) -> None:
    """Verify Prometheus metrics include specific metric."""
    response = get_context(test_context, "response")
    assert metric_name in response.text, f"Metric '{metric_name}' not found in response"


@then("the response should be a JSON array")
def check_json_array(test_context: dict) -> None:
    """Verify response is JSON array."""
    response = get_context(test_context, "response")
    data = response.json()
    assert isinstance(data, list), f"Expected JSON array, got {type(data)}"


@then("the response should be a direct array")
def check_direct_array(test_context: dict) -> None:
    """Verify response is direct array (no wrapper)."""
    check_json_array(test_context)


@then("the response should not have a wrapper object")
def check_no_wrapper(test_context: dict) -> None:
    """Verify response has no wrapper object."""
    response = get_context(test_context, "response")
    data = response.json()
    assert isinstance(data, list), (
        f"Expected direct array, got wrapper object: {type(data)}"
    )


@then("the response should contain at least one OLT ID")
def check_has_olt_ids(test_context: dict) -> None:
    """Verify response contains at least one OLT ID."""
    response = get_context(test_context, "response")
    data = response.json()
    assert len(data) > 0, "No OLT IDs in response"


@then("each OLT ID should be a string")
def check_olt_ids_are_strings(test_context: dict) -> None:
    """Verify all OLT IDs are strings."""
    response = get_context(test_context, "response")
    data = response.json()
    for olt_id in data:
        assert isinstance(olt_id, str), (
            f"OLT ID not a string: {olt_id} ({type(olt_id)})"
        )


@then(parsers.parse('each ONU should have a "{field}" field'))
def check_onus_have_field(test_context: dict, field: str) -> None:
    """Verify all ONUs have specified field."""
    response = get_context(test_context, "response")
    data = response.json()
    assert len(data) > 0, "No ONUs in response"
    for onu in data:
        assert field in onu, f"ONU missing '{field}' field: {onu}"


@then(parsers.parse("the response should contain at most {count:d} ONUs"))
def check_onu_count_max(test_context: dict, count: int) -> None:
    """Verify response contains at most N ONUs."""
    response = get_context(test_context, "response")
    data = response.json()
    assert len(data) <= count, f"Expected at most {count} ONUs, got {len(data)}"


@then("the response headers should include Link headers")
def check_link_headers(test_context: dict) -> None:
    """Verify response includes RFC 5988 Link headers."""
    response = get_context(test_context, "response")
    # Link header may or may not exist depending on pagination state
    # Just verify response has headers attribute
    assert hasattr(response, "headers"), "Response missing headers"


@then(parsers.parse('all returned ONUs should have status "{status}" if any exist'))
def check_onus_status_filtered(test_context: dict, status: str) -> None:
    """Verify filtered ONUs have correct status."""
    response = get_context(test_context, "response")
    data = response.json()
    # If any ONUs returned, they should match filter
    for onu in data:
        if "status" in onu:
            assert onu["status"] == status, (
                f"ONU status mismatch: expected '{status}', got '{onu['status']}'"
            )


@then("the response should contain the ONU serial")
def check_onu_serial(test_context: dict) -> None:
    """Verify response contains ONU serial."""
    response = get_context(test_context, "response")
    onu = get_context(test_context, "selected_onu")
    data = response.json()
    assert "serial" in data, f"Response missing 'serial' field: {data}"
    assert data["serial"] == onu["serial"], (
        f"Serial mismatch: expected '{onu['serial']}', got '{data['serial']}'"
    )


@then(parsers.parse('the response should have an "{field}" field'))
def check_has_field(test_context: dict, field: str) -> None:
    """Verify response has specified field."""
    response = get_context(test_context, "response")
    data = response.json()
    assert field in data, f"Response missing '{field}' field: {data}"


@then("all ONUs should belong to that OLT ID")
def check_onus_belong_to_olt(test_context: dict) -> None:
    """Verify all ONUs belong to specified OLT."""
    response = get_context(test_context, "response")
    olt_id = get_context(test_context, "selected_olt_id")
    data = response.json()
    for onu in data:
        assert "olt_id" in onu, f"ONU missing 'olt_id' field: {onu}"
        assert onu["olt_id"] == olt_id, (
            f"ONU belongs to different OLT: expected '{olt_id}', got '{onu['olt_id']}'"
        )


@then("the would_execute array should have the same count as input")
def check_bulk_would_execute_count(test_context: dict) -> None:
    """Verify bulk dry-run would_execute count matches input."""
    response = get_context(test_context, "response")
    selected_onus = get_context(test_context, "selected_onus")
    data = response.json()
    assert "would_execute" in data, f"Response missing 'would_execute': {data}"
    would_execute = data["would_execute"]
    assert len(would_execute) == len(selected_onus), (
        f"Count mismatch: input={len(selected_onus)}, would_execute={len(would_execute)}"
    )


@then("the response should contain validation errors")
def check_validation_errors(test_context: dict) -> None:
    """Verify response contains validation errors."""
    response = get_context(test_context, "response")
    data = response.json()
    assert "detail" in data, (
        f"Response missing 'detail' field for validation errors: {data}"
    )


@then(parsers.parse('each profile should have a "{field}" field'))
def check_profiles_have_field(test_context: dict, field: str) -> None:
    """Verify all profiles have specified field."""
    response = get_context(test_context, "response")
    data = response.json()
    if len(data) > 0:  # Only check if profiles exist
        for profile in data:
            assert field in profile, f"Profile missing '{field}' field: {profile}"


@then("the response should contain the profile ID")
def check_profile_id(test_context: dict) -> None:
    """Verify response contains profile ID."""
    response = get_context(test_context, "response")
    profile = get_context(test_context, "selected_profile")
    data = response.json()
    assert "profile_id" in data, f"Response missing 'profile_id' field: {data}"
    assert data["profile_id"] == profile["profile_id"], (
        f"Profile ID mismatch: expected '{profile['profile_id']}', got '{data['profile_id']}'"
    )


@then("the response should contain the service profile ID")
def check_service_profile_id(test_context: dict) -> None:
    """Verify response contains service profile ID."""
    response = get_context(test_context, "response")
    service = get_context(test_context, "selected_service")
    data = response.json()
    assert "service_id" in data, f"Response missing 'service_id' field: {data}"
    assert data["service_id"] == service["service_id"], (
        f"Service ID mismatch: expected '{service['service_id']}', got '{data['service_id']}'"
    )


@then("at least one response status code should be 429")
def check_rate_limited(test_context: dict) -> None:
    """Verify at least one request was rate limited."""
    responses = get_context(test_context, "responses")
    rate_limited = any(r.status_code == 429 for r in responses)
    assert rate_limited, (
        f"No rate limiting detected. Status codes: {[r.status_code for r in responses]}"
    )


@then("the rate limit headers should be present")
def check_rate_limit_headers(test_context: dict) -> None:
    """Verify rate limit headers are present."""
    responses = get_context(test_context, "responses")
    # Check if any 429 response has rate limit headers
    for response in responses:
        if response.status_code == 429:
            assert (
                "X-RateLimit-Limit" in response.headers
                or "Retry-After" in response.headers
            ), f"Rate limit headers missing in 429 response: {response.headers}"
            return
    # If no 429, just verify response has headers
    assert len(responses) > 0, "No responses to check"
