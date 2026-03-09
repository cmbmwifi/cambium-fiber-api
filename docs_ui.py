"""Custom documentation UI components with version selector and breadcrumbs.

This module provides enhanced Swagger UI HTML templates that include:
- Version selector dropdown for easy navigation between API versions
- Breadcrumb navigation showing current API version
- Custom styling following FastAPI best practices
"""

from fastapi.responses import HTMLResponse


def get_custom_swagger_ui_html(
    *,
    openapi_url: str,
    title: str,
    version: str,
    is_v1: bool = False,
    first_oauth_client_id: str | None = None,
) -> HTMLResponse:
    """Generate custom Swagger UI HTML with version selector, breadcrumbs, and curl examples.

    Args:
        openapi_url: URL to the OpenAPI JSON schema
        title: Page title to display
        version: API version string (e.g., "v2" or "v1")
        is_v1: Whether this is the v1 (legacy) documentation
        first_oauth_client_id: First OAuth client ID for curl examples (None if no clients)

    Returns:
        HTMLResponse with custom Swagger UI HTML including navigation enhancements and
        interactive curl examples with dynamic credential substitution

    Example:
        >>> html = get_custom_swagger_ui_html(
        ...     openapi_url="/openapi.json",
        ...     title="API v2",
        ...     version="v2",
        ...     is_v1=False,
        ...     first_oauth_client_id="admin"
        ... )
    """
    custom_css = """
    <style>
        /* Cambium Networks branding */
        .cambium-header {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            height: 60px;
            background: white;
            border-bottom: 3px solid #003A70;
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 0 20px;
            z-index: 9999;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }

        .cambium-header-left {
            display: flex;
            align-items: center;
            gap: 16px;
        }

        .cambium-header img {
            height: 64px;
            width: auto;
        }

        .cambium-header-title {
            font-size: 18px;
            font-weight: 600;
            color: #003A70;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        }

        .cambium-header-right {
            display: flex;
            align-items: center;
            gap: 12px;
        }

        .setup-link {
            display: flex;
            align-items: center;
            gap: 6px;
            padding: 8px 12px;
            background: #f3f4f6;
            border: 1px solid #d1d5db;
            border-radius: 6px;
            text-decoration: none;
            color: #374151;
            font-size: 14px;
            font-weight: 500;
            transition: all 0.2s;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        }

        .setup-link:hover {
            background: #003A70;
            color: white;
            border-color: #003A70;
        }

        .setup-icon {
            width: 16px;
            height: 16px;
        }

        .cambium-footer {
            position: fixed;
            bottom: 0;
            left: 0;
            right: 0;
            height: 40px;
            background: #f9fafb;
            border-top: 1px solid #e5e7eb;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 13px;
            color: #6b7280;
            z-index: 9999;
        }

        /* Version selector dropdown styling */
        .api-version-selector {
            position: fixed;
            top: 70px;
            right: 20px;
            z-index: 10000;
            background: white;
            padding: 8px 12px;
            border-radius: 4px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.15);
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        }

        .api-version-selector select {
            padding: 6px 30px 6px 10px;
            border: 1px solid #d1d5db;
            border-radius: 4px;
            font-size: 14px;
            cursor: pointer;
            background: white;
            appearance: none;
            background-image: url("data:image/svg+xml;charset=UTF-8,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3e%3cpolyline points='6 9 12 15 18 9'%3e%3c/polyline%3e%3c/svg%3e");
            background-repeat: no-repeat;
            background-position: right 6px center;
            background-size: 16px;
        }

        .api-version-selector select:hover {
            border-color: #3b82f6;
        }

        .api-version-selector select:focus {
            outline: none;
            border-color: #003A70;
            box-shadow: 0 0 0 3px rgba(0, 58, 112, 0.1);
        }

        /* Breadcrumb navigation */
        .api-breadcrumb {
            position: fixed;
            top: 70px;
            left: 20px;
            z-index: 10000;
            background: white;
            padding: 8px 16px;
            border-radius: 4px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.15);
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            font-size: 14px;
            display: flex;
            align-items: center;
            gap: 8px;
        }

        .api-breadcrumb a {
            color: #003A70;
            text-decoration: none;
            font-weight: 500;
        }

        .api-breadcrumb a:hover {
            text-decoration: underline;
        }

        .api-breadcrumb .separator {
            color: #9ca3af;
            user-select: none;
        }

        .api-breadcrumb .current {
            color: #1f2937;
            font-weight: 600;
        }

        .api-breadcrumb .badge {
            display: inline-block;
            padding: 2px 8px;
            border-radius: 12px;
            font-size: 11px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .api-breadcrumb .badge-current {
            background: #10b981;
            color: white;
        }

        .api-breadcrumb .badge-legacy {
            background: #f59e0b;
            color: white;
        }

        /* Adjust Swagger UI to not overlap with our custom elements */
        .swagger-ui {
            padding-top: 120px;
            padding-bottom: 50px;
        }

        /* Dark mode support */
        @media (prefers-color-scheme: dark) {
            .api-version-selector,
            .api-breadcrumb {
                background: #1f2937;
                color: #f9fafb;
            }

            .api-version-selector select {
                background: #374151;
                color: #f9fafb;
                border-color: #4b5563;
            }

            .api-breadcrumb a {
                color: #65A4EF;
            }

            .api-breadcrumb .current {
                color: #f9fafb;
            }

            .cambium-header {
                background: #1f2937;
                border-bottom-color: #65A4EF;
            }

            .cambium-header-title {
                color: #f9fafb;
            }

            .setup-link {
                background: #374151;
                border-color: #4b5563;
                color: #f9fafb;
            }

            .setup-link:hover {
                background: #65A4EF;
                border-color: #65A4EF;
            }

            .cambium-footer {
                background: #1f2937;
                border-top-color: #374151;
                color: #9ca3af;
            }
        }
    </style>
    """

    cambium_header = """
    <div class="cambium-header">
        <div class="cambium-header-left">
            <img src="/static/images/CN_logo_horizontal_reversed.png" alt="Cambium Networks">
            <span class="cambium-header-title">Cambium Fiber API</span>
        </div>
        <div class="cambium-header-right">
            <a href="/setup" class="setup-link">
                <svg class="setup-icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"></path>
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"></path>
                </svg>
                Setup
            </a>
        </div>
    </div>
    """

    cambium_footer = """
    <div class="cambium-footer">
        © 2026 Cambium Networks, Inc.
    </div>
    """

    version_selector = f"""
    <div class="api-version-selector">
        <select id="version-selector" aria-label="API Version Selector">
            <option value="/docs" {"selected" if not is_v1 else ""}>v2 API (Recommended)</option>
            <option value="/docs-v1" {"selected" if is_v1 else ""}>v1 API (Legacy)</option>
        </select>
    </div>
    """

    breadcrumb_badge = (
        '<span class="badge badge-current">Current</span>'
        if not is_v1
        else '<span class="badge badge-legacy">Legacy</span>'
    )
    breadcrumb = f"""
    <div class="api-breadcrumb">
        <a href="/">Home</a>
        <span class="separator">&rsaquo;</span>
        <span class="current">API {version} {breadcrumb_badge}</span>
    </div>
    """

    curl_examples_panel = ""
    if not is_v1:
        if first_oauth_client_id:
            client_id_value = first_oauth_client_id
            client_id_note = f"<small>Using first OAuth client: <code>{first_oauth_client_id}</code></small>"
        else:
            client_id_value = "YOUR_CLIENT_ID"
            client_id_note = '<small class="warning">⚠️ No OAuth clients found. Create one with: <code>python scripts/manage_oauth_clients.py add my-client read,write</code></small>'

        curl_examples_panel = f"""
        <div id="curl-examples-panel" style="margin: 20px; padding: 20px; background: #f9fafb; border: 1px solid #d1d5db; border-radius: 8px; margin-top: 140px;">
            <h2 style="margin-top: 0; color: #003A70; font-size: 20px; display: flex; align-items: center; justify-content: space-between;">
                <span>🚀 Quick Start: Testing the API</span>
                <button id="toggle-curl-examples" style="background: none; border: 1px solid #d1d5db; padding: 6px 12px; border-radius: 4px; cursor: pointer; font-size: 14px;">
                    Collapse
                </button>
            </h2>
            <div id="curl-examples-content">
                {client_id_note}

                <div style="background: #e0f2fe; border-left: 4px solid #0284c7; padding: 12px 16px; margin: 16px 0; border-radius: 4px;">
                    <p style="margin: 0; color: #0c4a6e; font-weight: 600;">
                        🔐 Easiest Way: Use the "Authorize" button below!
                    </p>
                    <p style="margin: 8px 0 0 0; color: #075985; font-size: 14px;">
                        Click the green "Authorize" button, enter your client_id and client_secret,
                        click "Authorize", then "Close". All API requests will automatically include your token.
                    </p>
                </div>

                <h3 style="color: #374151; font-size: 16px; margin-top: 20px;">Alternative: Manual curl commands</h3>

                <h4 style="color: #4b5563; font-size: 14px; margin-top: 16px;">Step 1: Get OAuth Access Token</h4>
                <div style="position: relative;">
                    <pre style="background: #1f2937; color: #f9fafb; padding: 16px; border-radius: 4px; overflow-x: auto; font-size: 13px; line-height: 1.5;"><code>curl -X POST http://localhost:8000/api/v2/access/token \\
  -d "grant_type=client_credentials" \\
  -d "client_id={client_id_value}" \\
  -d "client_secret=YOUR_CLIENT_SECRET"</code></pre>
                    <button class="copy-btn" data-clipboard-target="curl-token" style="position: absolute; top: 12px; right: 12px; background: #003A70; color: white; border: none; padding: 6px 12px; border-radius: 4px; cursor: pointer; font-size: 12px;">
                        Copy
                    </button>
                </div>
                <p style="color: #6b7280; font-size: 14px; margin-top: 8px;">
                    <strong>Response:</strong> <code>{{"access_token": "eyJ...", "token_type": "bearer", "expires_in": 3600}}</code>
                </p>
                <p style="color: #6b7280; font-size: 14px;">
                    💡 <strong>Tip:</strong> Store the access_token for subsequent requests. Tokens expire after 1 hour.
                </p>

                <h4 style="color: #4b5563; font-size: 14px; margin-top: 24px;">Step 2: Make Authenticated API Call</h4>
                <div style="position: relative;">
                    <pre style="background: #1f2937; color: #f9fafb; padding: 16px; border-radius: 4px; overflow-x: auto; font-size: 13px; line-height: 1.5;"><code>curl -X GET "http://localhost:8000/api/v2/fiber/onus?limit=10" \\
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"</code></pre>
                    <button class="copy-btn" data-clipboard-target="curl-api" style="position: absolute; top: 12px; right: 12px; background: #003A70; color: white; border: none; padding: 6px 12px; border-radius: 4px; cursor: pointer; font-size: 12px;">
                        Copy
                    </button>
                </div>
                <p style="color: #6b7280; font-size: 14px; margin-top: 8px;">
                    <strong>Response:</strong> List of first 10 ONUs with pagination metadata
                </p>
            </div>
        </div>
        """

    version_selector_script = """
    <script>
        document.addEventListener('DOMContentLoaded', function() {
            // Version selector
            const versionSelector = document.getElementById('version-selector');
            if (versionSelector) {
                versionSelector.addEventListener('change', function() {
                    window.location.href = this.value;
                });
            }

            // Curl examples toggle
            const toggleBtn = document.getElementById('toggle-curl-examples');
            const curlContent = document.getElementById('curl-examples-content');
            if (toggleBtn && curlContent) {
                let isCollapsed = false;
                toggleBtn.addEventListener('click', function() {
                    isCollapsed = !isCollapsed;
                    curlContent.style.display = isCollapsed ? 'none' : 'block';
                    toggleBtn.textContent = isCollapsed ? 'Expand' : 'Collapse';
                });
            }

            // Copy to clipboard functionality
            const copyButtons = document.querySelectorAll('.copy-btn');
            copyButtons.forEach(function(btn) {
                btn.addEventListener('click', function() {
                    // Get the code element's text
                    const codeElement = this.previousElementSibling.querySelector('code');
                    const textToCopy = codeElement ? codeElement.textContent : '';

                    // Copy to clipboard
                    navigator.clipboard.writeText(textToCopy).then(function() {
                        // Visual feedback
                        const originalText = btn.textContent;
                        btn.textContent = 'Copied!';
                        btn.style.background = '#10b981';
                        setTimeout(function() {
                            btn.textContent = originalText;
                            btn.style.background = '#003A70';
                        }, 2000);
                    }).catch(function(err) {
                        console.error('Failed to copy:', err);
                        btn.textContent = 'Failed';
                        setTimeout(function() {
                            btn.textContent = 'Copy';
                        }, 2000);
                    });
                });
            });
        });
    </script>
    """

    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>{title}</title>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <link rel="stylesheet" type="text/css" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.9.0/swagger-ui.css">
        {custom_css}
    </head>
    <body>
        {cambium_header}
        {breadcrumb}
        {version_selector}
        {curl_examples_panel}
        <div id="swagger-ui"></div>
        {cambium_footer}
        <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.9.0/swagger-ui-bundle.js"></script>
        <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.9.0/swagger-ui-standalone-preset.js"></script>
        <script>
            window.onload = function() {{
                const ui = SwaggerUIBundle({{
                    url: '{openapi_url}',
                    dom_id: '#swagger-ui',
                    presets: [
                        SwaggerUIBundle.presets.apis,
                        SwaggerUIStandalonePreset
                    ],
                    layout: "StandaloneLayout",
                    deepLinking: true,
                    showExtensions: true,
                    showCommonExtensions: true,
                    syntaxHighlight: {{
                        theme: "monokai"
                    }},
                    displayRequestDuration: true,
                    filter: true,
                    tryItOutEnabled: true,
                    persistAuthorization: true
                }});
                window.ui = ui;
            }};
        </script>
        {version_selector_script}
    </body>
    </html>
    """

    return HTMLResponse(content=html)

