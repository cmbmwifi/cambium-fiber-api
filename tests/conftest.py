"""Production validation test fixtures.

Provides pytest fixtures for production API testing with real OAuth authentication.
Tests run against deployed API instances using environment configuration.
"""

import json
import os
import sys
from typing import Any, Generator

import pytest
import requests


def _load_connections_credentials() -> tuple[str | None, str | None]:
    """Load OAuth client_id and plaintext client_secret from connections.json.

    Searches for connections.json starting from the project root (two levels up
    from pub/tests/).  Only clients that have a plaintext ``client_secret``
    field *and* are enabled are considered, since the test runner must post the
    plaintext to /api/v2/access/token.

    Returns:
        (client_id, client_secret) tuple, or (None, None) when not found.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.normpath(os.path.join(here, "..", "..", "connections.json")),
        os.path.normpath(os.path.join(here, "connections.json")),
    ]
    for path in candidates:
        if not os.path.exists(path):
            continue
        try:
            with open(path) as fh:
                config = json.load(fh)
            clients = config.get("oauth", {}).get(
                "clients", config.get("oauth_clients", [])
            )
            for client in clients:
                if client.get("enabled", True) and "client_secret" in client:
                    return client["client_id"], client["client_secret"]
        except Exception:
            pass
    return None, None


# Ensure test root is on path so step definitions can be imported
sys.path.insert(0, os.path.dirname(__file__))
from steps import production_steps  # noqa: F401


@pytest.hookimpl(hookwrapper=True)
def pytest_runtest_makereport(item: pytest.Item, call: pytest.CallInfo):
    """Convert skipped tests to failures — skips are never allowed.

    A skip means something is broken or misconfigured. Every skip is a real
    failure and must be treated as such so the validation suite always reflects
    the true state of the deployment.
    """
    outcome = yield
    rep = outcome.get_result()
    # Unconditionally promote any skip to a failure.
    if rep.skipped:
        if isinstance(rep.longrepr, tuple):
            _, _, reason = rep.longrepr
        else:
            reason = str(rep.longrepr)
        rep.outcome = "failed"
        rep.longrepr = f"SKIP PROMOTED TO FAIL — {reason}"


@pytest.fixture(scope="session")
def api_base_url() -> str:
    """Get API base URL from environment.

    Returns:
        Base URL for API requests (e.g., http://localhost:8192)

    Environment Variables:
        API_BASE_URL: Base URL for the deployed API (default: http://localhost:8192)
    """
    return os.getenv("API_BASE_URL", "http://localhost:8192")


@pytest.fixture(scope="session")
def oauth_client_id() -> str | None:
    """Get OAuth client ID from environment.

    Returns:
        OAuth client ID for authentication, or None if not set

    Environment Variables:
        OAUTH_CLIENT_ID: OAuth 2.0 client ID (optional)

    Notes:
        - Returns None if not set, allowing non-authenticated tests to run
        - Tests requiring OAuth will fail with clear message when requesting token
    """
    env_id = os.getenv("OAUTH_CLIENT_ID")
    if env_id:
        return env_id
    conn_id, _ = _load_connections_credentials()
    return conn_id


@pytest.fixture(scope="session")
def oauth_client_secret() -> str | None:
    """Get OAuth client secret from environment or connections.json.

    Returns:
        OAuth client secret for authentication, or None if not set

    Environment Variables:
        OAUTH_CLIENT_SECRET: OAuth 2.0 client secret (optional, overrides
        the value read from connections.json)

    Notes:
        - Falls back to the plaintext ``client_secret`` in connections.json
        - Returns None if no credential source is available
    """
    env_secret = os.getenv("OAUTH_CLIENT_SECRET")
    if env_secret:
        return env_secret
    _, conn_secret = _load_connections_credentials()
    return conn_secret


@pytest.fixture(scope="session")
def oauth_token(
    api_base_url: str, oauth_client_id: str | None, oauth_client_secret: str | None
) -> str:
    """Obtain OAuth access token for API authentication.

    Args:
        api_base_url: Base URL for API
        oauth_client_id: OAuth client ID
        oauth_client_secret: OAuth client secret

    Returns:
        Bearer token for API authentication

    Raises:
        pytest.skip: If OAuth credentials not provided
        AssertionError: If token acquisition fails
    """
    if not oauth_client_id or not oauth_client_secret:
        pytest.fail(
            "OAuth credentials not provided. Set OAUTH_CLIENT_ID and "
            "OAUTH_CLIENT_SECRET environment variables. "
            "See pub/tests/README.md for setup instructions."
        )

    response = requests.post(
        f"{api_base_url}/api/v2/access/token",
        data={
            "grant_type": "client_credentials",
            "client_id": oauth_client_id,
            "client_secret": oauth_client_secret,
        },
        timeout=10,
    )

    if response.status_code == 401:
        pytest.fail(
            "OAuth credentials provided via OAUTH_CLIENT_ID/OAUTH_CLIENT_SECRET "
            "were rejected by /api/v2/access/token (401). "
            "Update the environment credentials to match the deployed API."
        )

    assert response.status_code == 200, (
        f"OAuth token acquisition failed: {response.status_code} - {response.text}"
    )

    token_data = response.json()
    assert "access_token" in token_data, f"Response missing access_token: {token_data}"

    return token_data["access_token"]


@pytest.fixture(scope="function")
def api_client(
    api_base_url: str, oauth_token: str
) -> Generator[requests.Session, None, None]:
    """Create authenticated API client session.

    Args:
        api_base_url: Base URL for API
        oauth_token: OAuth Bearer token

    Yields:
        requests.Session configured with Bearer authentication and base URL

    Notes:
        - Session automatically includes Authorization header
        - Relative URLs resolved against api_base_url
        - Session closed after test completion
    """
    session = requests.Session()
    session.headers.update(
        {
            "Authorization": f"Bearer {oauth_token}",
            "Content-Type": "application/json",
        }
    )

    # Configure session to handle relative URLs
    class BaseURLSession(requests.Session):
        def __init__(self, base_url: str):
            super().__init__()
            self.base_url = base_url

        def request(
            self, method: str, url: str, *args: Any, **kwargs: Any
        ) -> requests.Response:
            # If URL is relative, prepend base URL
            if not url.startswith(("http://", "https://")):
                url = f"{self.base_url}{url}"
            return super().request(method, url, *args, **kwargs)

    # Replace session with BaseURLSession
    base_session = BaseURLSession(api_base_url)
    base_session.headers.update(session.headers)

    try:
        yield base_session
    finally:
        base_session.close()


@pytest.fixture(scope="function")
def test_context() -> dict:
    """Provide mutable dictionary for sharing data between test steps.

    Returns:
        Empty dictionary for storing test context

    Notes:
        - Used to pass data between Given/When/Then steps
        - Scoped per test function (isolated between tests)
        - Common keys: response, access_token, selected_olt_id, selected_onu, etc.
    """
    return {}
