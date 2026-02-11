"""Production validation test fixtures.

Provides pytest fixtures for production API testing with real OAuth authentication.
Tests run against deployed API instances using environment configuration.
"""

import os
from typing import Any, Generator

import pytest
import requests


@pytest.fixture(scope="session")
def api_base_url() -> str:
    """Get API base URL from environment.

    Returns:
        Base URL for API requests (e.g., http://localhost:8000)

    Environment Variables:
        API_BASE_URL: Base URL for the deployed API (default: http://localhost:8000)
    """
    return os.getenv("API_BASE_URL", "http://localhost:8000")


@pytest.fixture(scope="session")
def oauth_client_id() -> str:
    """Get OAuth client ID from environment.

    Returns:
        OAuth client ID for authentication

    Environment Variables:
        OAUTH_CLIENT_ID: OAuth 2.0 client ID (required)

    Raises:
        ValueError: If OAUTH_CLIENT_ID not set
    """
    client_id = os.getenv("OAUTH_CLIENT_ID")
    if not client_id:
        raise ValueError(
            "OAUTH_CLIENT_ID environment variable not set. "
            "See pub/tests/README.md for setup instructions."
        )
    return client_id


@pytest.fixture(scope="session")
def oauth_client_secret() -> str:
    """Get OAuth client secret from environment.

    Returns:
        OAuth client secret for authentication

    Environment Variables:
        OAUTH_CLIENT_SECRET: OAuth 2.0 client secret (required)

    Raises:
        ValueError: If OAUTH_CLIENT_SECRET not set
    """
    client_secret = os.getenv("OAUTH_CLIENT_SECRET")
    if not client_secret:
        raise ValueError(
            "OAUTH_CLIENT_SECRET environment variable not set. "
            "See pub/tests/README.md for setup instructions."
        )
    return client_secret


@pytest.fixture(scope="session")
def oauth_token(
    api_base_url: str, oauth_client_id: str, oauth_client_secret: str
) -> str:
    """Obtain OAuth access token for API authentication.

    Args:
        api_base_url: Base URL for API
        oauth_client_id: OAuth client ID
        oauth_client_secret: OAuth client secret

    Returns:
        Bearer token for API authentication

    Raises:
        AssertionError: If token acquisition fails
    """
    response = requests.post(
        f"{api_base_url}/oauth/token",
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
