"""Production validation test fixtures.

Provides pytest fixtures for production API testing with real OAuth authentication.
Tests run against deployed API instances using environment configuration.
"""

import os
import sys
from typing import Any, Generator

import pytest
import requests

# Ensure test root is on path so step definitions can be imported
sys.path.insert(0, os.path.dirname(__file__))
from steps import production_steps  # noqa: F401


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
    return os.getenv("OAUTH_CLIENT_ID")


@pytest.fixture(scope="session")
def oauth_client_secret() -> str | None:
    """Get OAuth client secret from environment.

    Returns:
        OAuth client secret for authentication, or None if not set

    Environment Variables:
        OAUTH_CLIENT_SECRET: OAuth 2.0 client secret (optional)

    Notes:
        - Returns None if not set, allowing non-authenticated tests to run
        - Tests requiring OAuth will fail with clear message when requesting token
    """
    return os.getenv("OAUTH_CLIENT_SECRET")


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
        pytest.skip(
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
