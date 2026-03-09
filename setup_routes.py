"""
Setup wizard routes for initial API configuration.

Provides web-based configuration interface when connections.json is missing or invalid.
Used by cross-platform installers (install.sh, install.ps1) for first-time setup.
"""

import json
import secrets
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse, Response
from pydantic import BaseModel, Field, field_validator

from app.adapters.connection.credentials import OLTConnectionInfo
from app.adapters.connection.transport import OLTTransport
from app.adapters.session import Session
from app.auth import verify_docs_auth
from app.config import get_connections_path
from app.logging import logger

router = APIRouter(tags=["Setup Wizard"])


class OLTConfig(BaseModel):
    """OLT configuration model for setup wizard."""

    olt_id: str = Field(
        default="", description="Unique OLT identifier (optional for test connection)"
    )
    host: str = Field(..., description="OLT IP address or hostname")
    username: str = Field(
        default="", description="OLT username (optional if using group)"
    )
    password: str = Field(
        default="", description="OLT password (optional if using group)"
    )
    stack_id: str = Field(default="", description="Virtual stack ID (optional)")

    @field_validator("olt_id")
    @classmethod
    def validate_olt_id(cls, v: str) -> str:
        """Validate OLT ID format (only when provided)."""
        if v and len(v) < 3:
            raise ValueError("OLT ID must be at least 3 characters")
        return v

    @field_validator("host")
    @classmethod
    def validate_host(cls, v: str) -> str:
        """Validate host format."""
        if not v:
            raise ValueError("Host is required")
        return v


class GroupConfig(BaseModel):
    """Group configuration for shared credentials."""

    group_id: str = Field(..., description="Unique group identifier")
    username: str = Field(..., description="Shared username")
    password: str = Field(..., description="Shared password")
    suspension_profile: str = Field(
        default="default", description="Default suspension profile"
    )


class VirtualStackConfig(BaseModel):
    """Virtual stack configuration for organizational grouping."""

    stack_id: str = Field(..., description="Unique stack identifier")
    olt_ids: list[str] = Field(..., description="OLT IDs in this stack")
    groups: list[str] = Field(
        default_factory=list, description="Group IDs for this stack"
    )


class SetupConfig(BaseModel):
    """Setup configuration model supporting multiple OLTs, groups, and virtual stacks."""

    olts: list[OLTConfig] = Field(
        ..., description="List of OLT configurations", min_length=1
    )
    groups: list[GroupConfig] = Field(
        default_factory=list, description="Optional shared credential groups"
    )
    virtual_stacks: list[VirtualStackConfig] = Field(
        default_factory=list, description="Optional organizational stacks"
    )

    @field_validator("olts")
    @classmethod
    def validate_olts_have_ids(cls, v: list[OLTConfig]) -> list[OLTConfig]:
        """Ensure all OLTs have IDs when saving configuration."""
        for i, olt in enumerate(v):
            if not olt.olt_id or len(olt.olt_id) < 3:
                raise ValueError(
                    f"OLT #{i + 1}: OLT ID is required and must be at least 3 characters"
                )
        return v


def is_setup_needed() -> bool:
    """
    Check if setup wizard should be enabled.

    Returns True if connections.json is missing or invalid.
    """
    connections_path = get_connections_path()

    if not connections_path.exists():
        return True

    try:
        with open(connections_path, "r") as f:
            data = json.load(f)

        if not isinstance(data, dict):
            return True

        if "olts" not in data or not isinstance(data["olts"], list):
            return True

        if len(data["olts"]) == 0:
            return True

        if "oauth" not in data or not isinstance(data["oauth"], dict):
            return True

        return "clients" not in data["oauth"] or not isinstance(
            data["oauth"]["clients"], list
        )

    except (json.JSONDecodeError, KeyError):
        return True


def generate_oauth_client_secret() -> str:
    """Generate a secure OAuth client secret."""
    return secrets.token_urlsafe(32)


async def validate_suspension_profiles(
    config: SetupConfig,
) -> dict[str, list[str]] | None:
    """Validate that suspension profiles exist on all OLTs in virtual stacks.

    Args:
        config: Setup configuration with OLTs, groups, and virtual stacks

    Returns:
        Dictionary mapping OLT IDs to missing profile names, or None if all valid

    Raises:
        HTTPException: If OLT connection fails during validation
    """
    if not config.virtual_stacks:
        return None

    groups_map = {g.group_id: g for g in config.groups}
    olts_map = {o.olt_id: o for o in config.olts}
    missing_profiles: dict[str, list[str]] = {}

    for stack in config.virtual_stacks:
        suspension_profiles = set()
        for group_id in stack.groups:
            if group_id in groups_map:
                profile_name = groups_map[group_id].suspension_profile
                if profile_name and profile_name != "default":
                    suspension_profiles.add(profile_name)

        if not suspension_profiles:
            continue

        for olt_id in stack.olt_ids:
            if olt_id not in olts_map:
                continue

            olt_config = olts_map[olt_id]
            base_url = olt_config.host
            if not base_url.startswith(("http://", "https://")):
                base_url = f"https://{base_url}"
            if ":" not in base_url.split("//")[1]:
                base_url = f"{base_url}:443"

            username = olt_config.username
            password = olt_config.password

            if not username or not password:
                for group_id in stack.groups:
                    if group_id in groups_map:
                        group = groups_map[group_id]
                        username = group.username
                        password = group.password
                        break

            if not username or not password:
                continue

            try:
                conn_info = OLTConnectionInfo(
                    base_url=base_url,
                    username=username,
                    password=password,
                    id=olt_id,
                )
                transport = OLTTransport(conn_info, timeout=5)
                try:
                    session = Session(transport)
                    olt_services = session.olt.services
                    olt_service_names = {svc.name for svc in olt_services}

                    for profile_name in suspension_profiles:
                        if profile_name not in olt_service_names:
                            if olt_id not in missing_profiles:
                                missing_profiles[olt_id] = []
                            missing_profiles[olt_id].append(profile_name)

                finally:
                    transport.disconnect()

            except Exception as e:  # noqa: BLE001 - API endpoint error handling
                logger.error(
                    f"Setup wizard: Profile validation failed for {olt_id}: {e}"
                )
                raise HTTPException(
                    status_code=502,
                    detail=f"Failed to connect to OLT '{olt_id}' for profile validation: {e!s}",
                ) from None

    return missing_profiles if missing_profiles else None


@router.get(
    "/setup",
    response_class=HTMLResponse,
    include_in_schema=False,
    dependencies=[Depends(verify_docs_auth)],
)
async def get_setup_page(request: Request) -> Response:
    """
    Render the setup wizard page.

    Only accessible when connections.json is missing or invalid.
    Provides HTML form for OLT configuration and OAuth setup.
    """
    if not is_setup_needed():
        return RedirectResponse(url="/docs", status_code=303)

    html_content = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Cambium Fiber API - Setup Wizard</title>
        <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }

            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
                background: linear-gradient(135deg, #003A70 0%, #65A4EF 100%);
                min-height: 100vh;
                display: flex;
                align-items: center;
                justify-content: center;
                padding: 20px;
            }

            .container {
                background: white;
                border-radius: 12px;
                box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
                max-width: 600px;
                width: 100%;
                padding: 40px;
            }

            .logo {
                text-align: center;
                margin-bottom: 30px;
            }

            .logo img {
                max-width: 280px;
                height: auto;
            }

            h1 {
                color: #333;
                margin-bottom: 10px;
                font-size: 28px;
            }

            .subtitle {
                color: #666;
                margin-bottom: 30px;
                font-size: 14px;
            }

            .form-group {
                margin-bottom: 20px;
            }

            label {
                display: block;
                margin-bottom: 8px;
                color: #333;
                font-weight: 500;
                font-size: 14px;
            }

            input[type="text"],
            input[type="password"] {
                width: 100%;
                padding: 12px;
                border: 1px solid #ddd;
                border-radius: 6px;
                font-size: 14px;
                transition: border-color 0.3s;
            }

            input[type="text"]:focus,
            input[type="password"]:focus {
                outline: none;
                border-color: #003A70;
            }

            input.error {
                border-color: #dc3545;
                background-color: #fff5f5;
            }

            .error-message {
                color: #dc3545;
                font-size: 12px;
                margin-top: 4px;
                display: none;
            }

            .error-message.visible {
                display: block;
            }

            .btn {
                width: 100%;
                padding: 14px;
                background: #003A70;
                color: white;
                border: none;
                border-radius: 6px;
                font-size: 16px;
                font-weight: 600;
                cursor: pointer;
                transition: transform 0.2s, box-shadow 0.2s, background 0.3s;
            }

            .btn:hover {
                transform: translateY(-2px);
                box-shadow: 0 10px 20px rgba(0, 58, 112, 0.4);
                background: #65A4EF;
            }

            .btn:active {
                transform: translateY(0);
            }

            .btn:disabled {
                opacity: 0.6;
                cursor: not-allowed;
            }

            .test-btn {
                width: 100%;
                padding: 10px;
                background: #28a745;
                color: white;
                border: none;
                border-radius: 6px;
                font-size: 14px;
                font-weight: 500;
                cursor: pointer;
                margin-top: 10px;
                transition: background 0.3s;
            }

            .test-btn:hover {
                background: #218838;
            }

            .alert {
                padding: 12px;
                border-radius: 6px;
                margin-bottom: 20px;
                font-size: 14px;
            }

            .alert-success {
                background: #d4edda;
                color: #155724;
                border: 1px solid #c3e6cb;
            }

            .alert-error {
                background: #f8d7da;
                color: #721c24;
                border: 1px solid #f5c6cb;
            }

            .alert-info {
                background: #d1ecf1;
                color: #0c5460;
                border: 1px solid #bee5eb;
            }

                position: fixed;
                top: 20px;
                left: 50%;
                transform: translateX(-50%);
                z-index: 1000;
                min-width: 400px;
                max-width: 600px;
            }

                box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
                margin-bottom: 0;
            }

            .olt-section {
                border: 1px solid #ddd;
                border-radius: 6px;
                padding: 20px;
                margin-bottom: 20px;
                background: #f8f9fa;
            }

            .section-title {
                font-size: 18px;
                font-weight: 600;
                color: #333;
                margin-bottom: 15px;
            }

            .help-text {
                font-size: 12px;
                color: #666;
                margin-top: 4px;
            }

                display: none;
                text-align: center;
                margin: 20px 0;
            }

            .spinner {
                border: 3px solid #f3f3f3;
                border-top: 3px solid #003A70;
                border-radius: 50%;
                width: 40px;
                height: 40px;
                animation: spin 1s linear infinite;
                margin: 0 auto;
            }

            @keyframes spin {
                0% { transform: rotate(0deg); }
                100% { transform: rotate(360deg); }
            }

            .footer {
                margin-top: 30px;
                padding-top: 20px;
                border-top: 1px solid #e5e7eb;
                text-align: center;
                color: #6b7280;
                font-size: 13px;
            }

            .olt-entry {
                position: relative;
            }

            .olt-header {
                display: flex;
                justify-content: space-between;
                align-items: center;
                margin-bottom: 15px;
            }

            .remove-olt-btn {
                background: #dc3545;
                color: white;
                border: none;
                border-radius: 4px;
                padding: 6px 12px;
                font-size: 12px;
                cursor: pointer;
                transition: background 0.3s;
            }

            .remove-olt-btn:hover {
                background: #c82333;
            }

            .add-olt-btn {
                width: 100%;
                padding: 12px;
                background: #17a2b8;
                color: white;
                border: none;
                border-radius: 6px;
                font-size: 14px;
                font-weight: 500;
                cursor: pointer;
                margin-bottom: 20px;
                transition: background 0.3s;
            }

            .add-olt-btn:hover {
                background: #138496;
            }

            .group-entry, .stack-entry {
                background: white;
                border: 1px solid #ddd;
                border-radius: 6px;
                padding: 15px;
                margin-bottom: 12px;
                transition: all 0.3s ease;
            }

            .group-entry:hover, .stack-entry:hover {
                border-color: #003A70;
                box-shadow: 0 2px 8px rgba(0, 58, 112, 0.1);
            }

            .entry-header {
                display: flex;
                justify-content: space-between;
                align-items: center;
                margin-bottom: 10px;
            }

            .entry-collapsed .entry-header {
                margin-bottom: 0;
            }

            .entry-title {
                font-weight: 600;
                color: #333;
                font-size: 14px;
            }

            .entry-summary {
                display: flex;
                align-items: center;
                gap: 10px;
                flex: 1;
                cursor: pointer;
            }

            .entry-icon {
                font-size: 18px;
            }

            .entry-details {
                display: flex;
                flex-direction: column;
                gap: 2px;
            }

            .entry-id {
                font-weight: 600;
                color: #333;
            }

            .entry-meta {
                font-size: 12px;
                color: #666;
            }

            .entry-actions {
                display: flex;
                gap: 6px;
            }

            .edit-entry-btn, .remove-entry-btn, .save-entry-btn, .cancel-entry-btn {
                border: none;
                border-radius: 4px;
                padding: 6px 12px;
                font-size: 12px;
                cursor: pointer;
                font-weight: 500;
                transition: all 0.2s;
            }

            .edit-entry-btn {
                background: #17a2b8;
                color: white;
            }

            .edit-entry-btn:hover {
                background: #138496;
            }

            .remove-entry-btn {
                background: #dc3545;
                color: white;
            }

            .remove-entry-btn:hover {
                background: #c82333;
            }

            .save-entry-btn {
                background: #28a745;
                color: white;
            }

            .save-entry-btn:hover {
                background: #218838;
            }

            .cancel-entry-btn {
                background: #6c757d;
                color: white;
            }

            .cancel-entry-btn:hover {
                background: #5a6268;
            }

            .entry-form {
                display: none;
                margin-top: 15px;
            }

            .entry-expanded .entry-form {
                display: block;
            }

            .entry-collapsed .entry-summary {
                cursor: pointer;
            }

            .add-entry-btn {
                width: 100%;
                padding: 10px;
                background: #6f42c1;
                color: white;
                border: none;
                border-radius: 6px;
                font-size: 14px;
                cursor: pointer;
                margin-top: 10px;
                font-weight: 500;
                transition: background 0.3s;
            }

            .add-entry-btn:hover {
                background: #5a32a3;
            }
        </style>
    </head>
    <body>
        <div id="message-area"></div>

        <div class="container">
            <div class="logo">
                <img src="/static/images/CN_logo_horizontal_blueIcon_blackName.png" alt="Cambium Networks" onerror="this.style.display='none'">
            </div>
            <h1>🚀 Cambium Fiber API Setup</h1>
            <p class="subtitle">Configure your OLT connections to get started</p>

            <form id="setup-form">
                <!-- Credential Groups Section -->
                <div class="olt-section" style="background: #fff3cd; border-color: #ffc107;">
                    <div class="section-title" style="color: #856404;">🔑 Credential Groups</div>
                    <div class="help-text" style="margin-bottom: 15px;">
                        Create shared credential groups for OLTs that use the same username/password. Each OLT can then select which group to use.
                    </div>

                    <div id="groups-container"></div>

                    <button type="button" class="add-entry-btn" id="add-group-btn">
                        + Add New Credential Group
                    </button>
                </div>

                <!-- Virtual Stacks Section -->
                <div class="olt-section" style="background: #e8f4f8; border-color: #17a2b8;">
                    <div class="section-title" style="color: #17a2b8;">📚 Virtual Stacks</div>
                    <div class="help-text" style="margin-bottom: 15px;">
                        Create organizational groupings (virtual stacks) to organize your OLTs by location, region, or function.
                    </div>

                    <div id="stacks-container"></div>

                    <button type="button" class="add-entry-btn" id="add-stack-btn">
                        + Add New Virtual Stack
                    </button>
                </div>

                <div id="olt-entries-container">
                    <!-- OLT entries will be dynamically added here -->
                </div>

                <button type="button" class="add-olt-btn" id="add-olt-btn">
                    + Add Another OLT
                </button>

                <div id="loading">
                    <div class="spinner"></div>
                    <p style="margin-top: 10px; color: #666;">Saving configuration...</p>
                </div>

                <button type="submit" class="btn" id="submit-btn">
                    Complete Setup
                </button>
            </form>

            <div class="footer">
                © 2026 Cambium Networks, Inc.
            </div>
        </div>

        <script>
            const form = document.getElementById('setup-form');
            const submitBtn = document.getElementById('submit-btn');
            const addOltBtn = document.getElementById('add-olt-btn');
            const addGroupBtn = document.getElementById('add-group-btn');
            const addStackBtn = document.getElementById('add-stack-btn');
            const oltEntriesContainer = document.getElementById('olt-entries-container');
            const groupsContainer = document.getElementById('groups-container');
            const stacksContainer = document.getElementById('stacks-container');
            const messageArea = document.getElementById('message-area');
            const loading = document.getElementById('loading');

            let oltCount = 0;
            let groupCount = 0;
            let stackCount = 0;
            const validationState = {}; // Track validation state for each field

            /**
             * Validate hostname/identifier (RFC 1123 compliant, URL-safe)
             * Rules:
             * - Only alphanumeric characters and hyphens
             * - Cannot start or end with hyphen
             * - Length: 1-63 characters
             * - Case insensitive
             */
            function isValidHostnameIdentifier(value) {
                if (!value || typeof value !== 'string') return false;

                // Length check
                if (value.length < 1 || value.length > 63) return false;

                // Pattern check: alphanumeric and hyphens only
                const hostnamePattern = /^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$/;
                return hostnamePattern.test(value);
            }

            /**
             * Show validation error for a field
             */
            function showFieldError(fieldId, message) {
                const field = document.getElementById(fieldId);
                const errorEl = document.getElementById(fieldId + '_error');

                if (field) {
                    field.classList.add('error');
                    validationState[fieldId] = false;
                }

                if (errorEl) {
                    errorEl.textContent = message;
                    errorEl.classList.add('visible');
                }
            }

            /**
             * Clear validation error for a field
             */
            function clearFieldError(fieldId) {
                const field = document.getElementById(fieldId);
                const errorEl = document.getElementById(fieldId + '_error');

                if (field) {
                    field.classList.remove('error');
                    validationState[fieldId] = true;
                }

                if (errorEl) {
                    errorEl.textContent = '';
                    errorEl.classList.remove('visible');
                }
            }

            /**
             * Validate a hostname identifier field
             */
            function validateHostnameField(fieldId, fieldName) {
                const field = document.getElementById(fieldId);
                if (!field) return true;

                const value = field.value.trim();

                // If field is not required and empty, that's ok
                if (!field.required && !value) {
                    clearFieldError(fieldId);
                    return true;
                }

                // If field is required and empty
                if (field.required && !value) {
                    showFieldError(fieldId, `${fieldName} is required`);
                    return false;
                }

                // Validate format
                if (!isValidHostnameIdentifier(value)) {
                    showFieldError(fieldId, `${fieldName} must contain only letters, numbers, and hyphens. Cannot start or end with hyphen. Max 63 characters.`);
                    return false;
                }

                clearFieldError(fieldId);
                return true;
            }

            /**
             * Check if all validations pass
             */
            function isFormValid() {
                // Check all validation state entries
                for (const [fieldId, isValid] of Object.entries(validationState)) {
                    if (isValid === false) return false;
                }
                return true;
            }

            /**
             * Get all active group IDs
             */
            function getActiveGroups() {
                const groups = [];
                document.querySelectorAll('.group-entry').forEach(entry => {
                    const index = entry.dataset.groupIndex;
                    const groupId = document.getElementById(`group_id_${index}`)?.value;
                    if (groupId) groups.push({ id: groupId, index });
                });
                return groups;
            }

            /**
             * Get all active stack IDs
             */
            function getActiveStacks() {
                const stacks = [];
                document.querySelectorAll('.stack-entry').forEach(entry => {
                    const index = entry.dataset.stackIndex;
                    const stackId = document.getElementById(`stack_id_${index}`)?.value;
                    if (stackId) stacks.push({ id: stackId, index });
                });
                return stacks;
            }

            /**
             * Update all OLT dropdowns when groups/stacks change
             */
            function updateOltDropdowns() {
                const oltEntries = document.querySelectorAll('.olt-entry');
                oltEntries.forEach(entry => {
                    const index = entry.dataset.oltIndex;
                    updateOltGroupDropdown(index);
                    updateOltStackDropdown(index);
                });

                // Update stack summaries to reflect OLT assignment counts
                document.querySelectorAll('.stack-entry').forEach(entry => {
                    const index = entry.dataset.stackIndex;
                    if (entry.classList.contains('entry-collapsed')) {
                        updateStackSummary(index);
                    }
                });
            }

            /**
             * Update group dropdown for an OLT entry
             */
            function updateOltGroupDropdown(oltIndex) {
                const select = document.getElementById(`olt_group_${oltIndex}`);
                if (!select) return;

                const currentValue = select.value;
                const groups = getActiveGroups();

                // Clear and rebuild options
                select.innerHTML = '<option value="">-- Individual Credentials --</option>';
                groups.forEach(group => {
                    const option = document.createElement('option');
                    option.value = group.id;
                    option.textContent = group.id;
                    select.appendChild(option);
                });

                // Restore selection or default to first if available
                if (currentValue && groups.some(g => g.id === currentValue)) {
                    select.value = currentValue;
                } else if (groups.length > 0) {
                    select.value = groups[0].id;
                }

                // Show/hide credential fields based on selection
                toggleOltCredentialFields(oltIndex, select.value === '');
            }

            /**
             * Update stack dropdown for an OLT entry
             */
            function updateOltStackDropdown(oltIndex) {
                const select = document.getElementById(`olt_stack_${oltIndex}`);
                if (!select) return;

                const currentValue = select.value;
                const stacks = getActiveStacks();

                // Clear and rebuild options
                select.innerHTML = '<option value="">-- No Stack --</option>';
                stacks.forEach(stack => {
                    const option = document.createElement('option');
                    option.value = stack.id;
                    option.textContent = stack.id;
                    select.appendChild(option);
                });

                // Restore selection or default to first if available
                if (currentValue && stacks.some(s => s.id === currentValue)) {
                    select.value = currentValue;
                } else if (stacks.length > 0) {
                    select.value = stacks[0].id;
                }
            }

            /**
             * Toggle OLT credential fields visibility
             */
            function toggleOltCredentialFields(oltIndex, show) {
                const usernameField = document.getElementById(`olt_creds_${oltIndex}`);
                if (usernameField) {
                    usernameField.style.display = show ? 'block' : 'none';
                    // Update required attribute
                    const username = document.getElementById(`username_${oltIndex}`);
                    const password = document.getElementById(`password_${oltIndex}`);
                    if (username) username.required = show;
                    if (password) password.required = show;
                }
            }

            /**
             * Create a credential group entry with collapsible card UI
             */
            function createGroupEntry(index, isNew = false) {
                const entry = document.createElement('div');
                entry.className = isNew ? 'group-entry entry-expanded' : 'group-entry entry-collapsed';
                entry.dataset.groupIndex = index;

                entry.innerHTML = `
                    <div class="entry-header">
                        <div class="entry-summary" onclick="toggleGroupExpand(${index})">
                            <span class="entry-icon">🔑</span>
                            <div class="entry-details">
                                <div class="entry-id" id="group_display_id_${index}">New Credential Group</div>
                                <div class="entry-meta" id="group_display_meta_${index}">Click to configure</div>
                            </div>
                        </div>
                        <div class="entry-actions">
                            <button type="button" class="edit-entry-btn" onclick="editGroupEntry(${index})" style="${isNew ? 'display:none;' : ''}">Edit</button>
                            <button type="button" class="remove-entry-btn" onclick="removeGroupEntry(${index})">Delete</button>
                        </div>
                    </div>
                    <div class="entry-form">
                        <div class="form-group">
                            <label for="group_id_${index}">Group ID *</label>
                            <input type="text" id="group_id_${index}" name="group_id_${index}" required
                                   placeholder="e.g., default-auth" value="${index === 0 ? 'default-auth' : ''}">
                            <div class="help-text">Unique identifier for this credential group</div>
                            <div class="error-message" id="group_id_${index}_error"></div>
                        </div>
                        <div class="form-group">
                            <label for="group_username_${index}">Username *</label>
                            <input type="text" id="group_username_${index}" name="group_username_${index}" required value="admin">
                        </div>
                        <div class="form-group">
                            <label for="group_password_${index}">Password *</label>
                            <input type="password" id="group_password_${index}" name="group_password_${index}" required>
                        </div>
                        <div class="form-group">
                            <label for="group_suspension_${index}">Suspension Profile</label>
                            <input type="text" id="group_suspension_${index}" name="group_suspension_${index}" value="default">
                            <div class="help-text">Service profile to apply when suspending ONUs</div>
                        </div>
                        <div style="display: flex; gap: 10px; margin-top: 15px;">
                            <button type="button" class="save-entry-btn" onclick="saveGroupEntry(${index})">Save</button>
                            <button type="button" class="cancel-entry-btn" onclick="cancelGroupEntry(${index})" style="${isNew ? 'display:none;' : ''}">Cancel</button>
                        </div>
                    </div>
                `;

                // Add validation listener
                const groupIdField = entry.querySelector(`#group_id_${index}`);
                groupIdField.addEventListener('blur', function() {
                    validateHostnameField(this.id, 'Group ID');
                });
                groupIdField.addEventListener('input', function() {
                    updateGroupSummary(index);
                });

                const groupUsernameField = entry.querySelector(`#group_username_${index}`);
                groupUsernameField.addEventListener('input', function() {
                    updateGroupSummary(index);
                });

                return entry;
            }

            /**
             * Toggle group entry expand/collapse
             */
            function toggleGroupExpand(index) {
                const entry = document.querySelector(`.group-entry[data-group-index="${index}"]`);
                if (entry && entry.classList.contains('entry-collapsed')) {
                    editGroupEntry(index);
                }
            }

            /**
             * Edit group entry (expand form)
             */
            function editGroupEntry(index) {
                const entry = document.querySelector(`.group-entry[data-group-index="${index}"]`);
                if (entry) {
                    // Store original values for cancel
                    entry.dataset.originalId = document.getElementById(`group_id_${index}`).value;
                    entry.dataset.originalUsername = document.getElementById(`group_username_${index}`).value;
                    entry.dataset.originalPassword = document.getElementById(`group_password_${index}`).value;
                    entry.dataset.originalSuspension = document.getElementById(`group_suspension_${index}`).value;

                    entry.classList.remove('entry-collapsed');
                    entry.classList.add('entry-expanded');
                }
            }

            /**
             * Save group entry (collapse with validation)
             */
            function saveGroupEntry(index) {
                const groupId = document.getElementById(`group_id_${index}`).value.trim();
                const username = document.getElementById(`group_username_${index}`).value.trim();
                const password = document.getElementById(`group_password_${index}`).value;

                // Validate required fields
                if (!groupId) {
                    showMessage('Group ID is required', 'error');
                    return;
                }
                if (!username) {
                    showMessage('Username is required', 'error');
                    return;
                }
                if (!password) {
                    showMessage('Password is required', 'error');
                    return;
                }

                // Validate group ID format
                if (!isValidHostnameIdentifier(groupId)) {
                    showMessage('Group ID must be URL-safe (letters, numbers, hyphens only)', 'error');
                    return;
                }

                const entry = document.querySelector(`.group-entry[data-group-index="${index}"]`);
                if (entry) {
                    entry.classList.remove('entry-expanded');
                    entry.classList.add('entry-collapsed');
                    updateGroupSummary(index);
                    updateOltDropdowns();
                }
            }

            /**
             * Cancel group entry edit (restore original values)
             */
            function cancelGroupEntry(index) {
                const entry = document.querySelector(`.group-entry[data-group-index="${index}"]`);
                if (entry) {
                    // Restore original values
                    if (entry.dataset.originalId !== undefined) {
                        document.getElementById(`group_id_${index}`).value = entry.dataset.originalId;
                        document.getElementById(`group_username_${index}`).value = entry.dataset.originalUsername;
                        document.getElementById(`group_password_${index}`).value = entry.dataset.originalPassword;
                        document.getElementById(`group_suspension_${index}`).value = entry.dataset.originalSuspension;
                    }

                    entry.classList.remove('entry-expanded');
                    entry.classList.add('entry-collapsed');
                    updateGroupSummary(index);
                }
            }

            /**
             * Update group summary display
             */
            function updateGroupSummary(index) {
                const groupId = document.getElementById(`group_id_${index}`)?.value.trim() || 'Unnamed';
                const username = document.getElementById(`group_username_${index}`)?.value.trim() || '';

                const displayId = document.getElementById(`group_display_id_${index}`);
                const displayMeta = document.getElementById(`group_display_meta_${index}`);

                if (displayId) displayId.textContent = groupId;
                if (displayMeta) displayMeta.textContent = username ? `Username: ${username}` : 'No username set';
            }

            /**
             * Create a virtual stack entry with collapsible card UI
             */
            function createStackEntry(index, isNew = false) {
                const entry = document.createElement('div');
                entry.className = isNew ? 'stack-entry entry-expanded' : 'stack-entry entry-collapsed';
                entry.dataset.stackIndex = index;

                entry.innerHTML = `
                    <div class="entry-header">
                        <div class="entry-summary" onclick="toggleStackExpand(${index})">
                            <span class="entry-icon">📚</span>
                            <div class="entry-details">
                                <div class="entry-id" id="stack_display_id_${index}">New Virtual Stack</div>
                                <div class="entry-meta" id="stack_display_meta_${index}">Click to configure</div>
                            </div>
                        </div>
                        <div class="entry-actions">
                            <button type="button" class="edit-entry-btn" onclick="editStackEntry(${index})" style="${isNew ? 'display:none;' : ''}">Edit</button>
                            <button type="button" class="remove-entry-btn" onclick="removeStackEntry(${index})">Delete</button>
                        </div>
                    </div>
                    <div class="entry-form">
                        <div class="form-group">
                            <label for="stack_id_${index}">Stack ID *</label>
                            <input type="text" id="stack_id_${index}" name="stack_id_${index}" required
                                   placeholder="e.g., 123-Example-St-Dallas-TX">
                            <div class="help-text">Name for this organizational group. Must be URL-safe: letters, numbers, and hyphens only.</div>
                            <div class="error-message" id="stack_id_${index}_error"></div>
                        </div>
                        <div style="display: flex; gap: 10px; margin-top: 15px;">
                            <button type="button" class="save-entry-btn" onclick="saveStackEntry(${index})">Save</button>
                            <button type="button" class="cancel-entry-btn" onclick="cancelStackEntry(${index})" style="${isNew ? 'display:none;' : ''}">Cancel</button>
                        </div>
                    </div>
                `;

                // Add validation listener
                const stackIdField = entry.querySelector(`#stack_id_${index}`);
                stackIdField.addEventListener('blur', function() {
                    validateHostnameField(this.id, 'Stack ID');
                });
                stackIdField.addEventListener('input', function() {
                    updateStackSummary(index);
                });

                return entry;
            }

            /**
             * Toggle stack entry expand/collapse
             */
            function toggleStackExpand(index) {
                const entry = document.querySelector(`.stack-entry[data-stack-index="${index}"]`);
                if (entry && entry.classList.contains('entry-collapsed')) {
                    editStackEntry(index);
                }
            }

            /**
             * Edit stack entry (expand form)
             */
            function editStackEntry(index) {
                const entry = document.querySelector(`.stack-entry[data-stack-index="${index}"]`);
                if (entry) {
                    // Store original value for cancel
                    entry.dataset.originalId = document.getElementById(`stack_id_${index}`).value;

                    entry.classList.remove('entry-collapsed');
                    entry.classList.add('entry-expanded');
                }
            }

            /**
             * Save stack entry (collapse with validation)
             */
            function saveStackEntry(index) {
                const stackId = document.getElementById(`stack_id_${index}`).value.trim();

                // Validate required fields
                if (!stackId) {
                    showMessage('Stack ID is required', 'error');
                    return;
                }

                // Validate stack ID format
                if (!isValidHostnameIdentifier(stackId)) {
                    showMessage('Stack ID must be URL-safe (letters, numbers, hyphens only)', 'error');
                    return;
                }

                const entry = document.querySelector(`.stack-entry[data-stack-index="${index}"]`);
                if (entry) {
                    entry.classList.remove('entry-expanded');
                    entry.classList.add('entry-collapsed');
                    updateStackSummary(index);
                    updateOltDropdowns();
                }
            }

            /**
             * Cancel stack entry edit (restore original value)
             */
            function cancelStackEntry(index) {
                const entry = document.querySelector(`.stack-entry[data-stack-index="${index}"]`);
                if (entry) {
                    // Restore original value
                    if (entry.dataset.originalId !== undefined) {
                        document.getElementById(`stack_id_${index}`).value = entry.dataset.originalId;
                    }

                    entry.classList.remove('entry-expanded');
                    entry.classList.add('entry-collapsed');
                    updateStackSummary(index);
                }
            }

            /**
             * Update stack summary display
             */
            function updateStackSummary(index) {
                const stackId = document.getElementById(`stack_id_${index}`)?.value.trim() || 'Unnamed';

                const displayId = document.getElementById(`stack_display_id_${index}`);
                const displayMeta = document.getElementById(`stack_display_meta_${index}`);

                if (displayId) displayId.textContent = stackId;
                if (displayMeta) {
                    // Count how many OLTs are assigned to this stack
                    const oltCount = document.querySelectorAll(`select[id^="olt_stack_"] option[value="${stackId}"]:checked`).length;
                    displayMeta.textContent = oltCount > 0 ? `${oltCount} OLT${oltCount !== 1 ? 's' : ''} assigned` : 'No OLTs assigned yet';
                }
            }

            function addGroupEntry() {
                const entry = createGroupEntry(groupCount, true);
                groupsContainer.appendChild(entry);
                groupCount++;
                updateGroupSummary(groupCount - 1);
            }

            function removeGroupEntry(index) {
                const entry = document.querySelector(`.group-entry[data-group-index="${index}"]`);
                if (entry) {
                    entry.remove();
                    updateOltDropdowns();
                }
            }

            function addStackEntry() {
                const entry = createStackEntry(stackCount, true);
                stacksContainer.appendChild(entry);
                stackCount++;
                updateStackSummary(stackCount - 1);
            }

            function removeStackEntry(index) {
                const entry = document.querySelector(`.stack-entry[data-stack-index="${index}"]`);
                if (entry) {
                    entry.remove();
                    updateOltDropdowns();
                }
            }

            function showMessage(message, type) {
                messageArea.innerHTML = `
                    <div class="alert alert-${type}">
                        ${message}
                    </div>
                `;
                // Auto-clear after 5 seconds for non-critical messages
                if (type !== 'success' || !message.includes('Setup Complete')) {
                    setTimeout(() => {
                        messageArea.innerHTML = '';
                    }, 5000);
                }

                // Scroll to top to ensure message is visible
                window.scrollTo({ top: 0, behavior: 'smooth' });
            }

            function createOltEntry(index) {
                const oltEntry = document.createElement('div');
                oltEntry.className = 'olt-section olt-entry';
                oltEntry.dataset.oltIndex = index;

                const groups = getActiveGroups();
                const stacks = getActiveStacks();

                oltEntry.innerHTML = `
                    <div class="olt-header">
                        <div class="section-title">OLT Configuration ${index > 0 ? '#' + (index + 1) : ''}</div>
                        ${index > 0 ? '<button type="button" class="remove-olt-btn" onclick="removeOltEntry(' + index + ')">Remove</button>' : ''}
                    </div>

                    <div class="form-group">
                        <label for="host_${index}">IP Address / Hostname *</label>
                        <input type="text" id="host_${index}" name="host_${index}" required
                               placeholder="e.g., 192.168.0.1">
                        <div class="help-text">Network address where the OLT can be reached</div>
                    </div>

                    <div class="form-group">
                        <label for="olt_group_${index}">Credential Group</label>
                        <select id="olt_group_${index}" name="olt_group_${index}">
                            <option value="">-- Individual Credentials --</option>
                            ${groups.map(g => `<option value="${g.id}"${groups.length > 0 && g.index === 0 ? ' selected' : ''}>${g.id}</option>`).join('')}
                        </select>
                        <div class="help-text">Select a credential group or use individual credentials below</div>
                    </div>

                    <div id="olt_creds_${index}" style="display: ${groups.length === 0 ? 'block' : 'none'};">
                        <div class="form-group">
                            <label for="username_${index}">Username *</label>
                            <input type="text" id="username_${index}" name="username_${index}" ${groups.length === 0 ? 'required' : ''}
                                   value="admin">
                            <div class="help-text">OLT administrative username</div>
                        </div>

                        <div class="form-group">
                            <label for="password_${index}">Password *</label>
                            <input type="password" id="password_${index}" name="password_${index}" ${groups.length === 0 ? 'required' : ''}
                                   placeholder="Enter OLT password">
                            <div class="help-text">OLT administrative password</div>
                        </div>
                    </div>

                    <button type="button" class="test-btn" onclick="testConnection(${index})">
                        ✓ Test Connection
                    </button>

                    <div class="form-group" style="margin-top: 1rem;">
                        <label for="olt_id_${index}">OLT ID *</label>
                        <input type="text" id="olt_id_${index}" name="olt_id_${index}" required
                               placeholder="Auto-filled after test connection">
                        <div class="help-text">Unique identifier for this OLT. Auto-populated from MSN after successful connection test. Must be URL-safe: letters, numbers, and hyphens only.</div>
                        <div class="error-message" id="olt_id_${index}_error"></div>
                    </div>

                    <div class="form-group">
                        <label for="olt_stack_${index}">Virtual Stack</label>
                        <select id="olt_stack_${index}" name="olt_stack_${index}">
                            <option value="">-- No Stack --</option>
                            ${stacks.map(s => `<option value="${s.id}"${stacks.length > 0 && s.index === 0 ? ' selected' : ''}>${s.id}</option>`).join('')}
                        </select>
                        <div class="help-text">Assign this OLT to an organizational group</div>
                    </div>
                `;

                // Add event listener for group dropdown
                const groupSelect = oltEntry.querySelector(`#olt_group_${index}`);
                groupSelect.addEventListener('change', function() {
                    toggleOltCredentialFields(index, this.value === '');
                });

                // Add event listener for stack dropdown to update stack summaries
                const stackSelect = oltEntry.querySelector(`#olt_stack_${index}`);
                stackSelect.addEventListener('change', function() {
                    // Update all stack summaries when OLT assignment changes
                    document.querySelectorAll('.stack-entry').forEach(entry => {
                        const stackIndex = entry.dataset.stackIndex;
                        if (entry.classList.contains('entry-collapsed')) {
                            updateStackSummary(stackIndex);
                        }
                    });
                });

                return oltEntry;
            }

            function addOltEntry() {
                const newEntry = createOltEntry(oltCount);
                oltEntriesContainer.appendChild(newEntry);

                // Add blur validation listener for the OLT ID field
                const oltIdField = document.getElementById(`olt_id_${oltCount}`);
                if (oltIdField) {
                    oltIdField.addEventListener('blur', function() {
                        validateHostnameField(this.id, 'OLT ID');
                    });
                }

                oltCount++;
            }

            function removeOltEntry(index) {
                const entry = document.querySelector(`[data-olt-index="${index}"]`);
                if (entry) {
                    entry.remove();
                }
            }

            async function testConnection(index) {
                const oltId = document.getElementById(`olt_id_${index}`).value;
                const host = document.getElementById(`host_${index}`).value;
                const groupId = document.getElementById(`olt_group_${index}`).value;

                let username, password;

                if (groupId) {
                    // Get credentials from selected group
                    const groups = getActiveGroups();
                    const group = groups.find(g => g.id === groupId);
                    if (group) {
                        username = document.getElementById(`group_username_${group.index}`).value;
                        password = document.getElementById(`group_password_${group.index}`).value;
                    }
                } else {
                    // Get individual credentials
                    username = document.getElementById(`username_${index}`).value;
                    password = document.getElementById(`password_${index}`).value;
                }

                if (!host || !username || !password) {
                    showMessage(`Please fill in IP address and credentials for OLT ${index + 1} before testing`, 'error');
                    return;
                }

                const testBtn = event.target;
                testBtn.disabled = true;
                testBtn.textContent = '⏳ Testing...';

                try {
                    const response = await fetch('/setup/test', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ olt_id: oltId || '', host, username, password })
                    });

                    const result = await response.json();

                    if (response.ok) {
                        // Auto-populate OLT ID with MSN if available
                        if (result.msn && !oltId) {
                            document.getElementById(`olt_id_${index}`).value = result.msn;
                        }

                        let message = `✓ Connection successful to ${host}!`;
                        if (result.msn) {
                            message += `\\n  MSN: ${result.msn}${!oltId ? ' (auto-filled)' : ''}`;
                        }
                        if (result.device_name) {
                            message += `\\n  Device Name: ${result.device_name}`;
                        }
                        if (result.total_services) {
                            message += `\\n  Service Profiles: ${result.total_services} available`;
                            if (result.service_profiles && result.service_profiles.length > 0) {
                                const profileNames = result.service_profiles.map(p => p.name).join(', ');
                                message += `\\n  (${profileNames}${result.total_services > result.service_profiles.length ? ', ...' : ''})`;
                            }
                        }
                        showMessage(message, 'success');
                    } else {
                        showMessage(`✗ Connection failed to ${host}: ${result.detail || 'Unknown error'}`, 'error');
                    }
                } catch (error) {
                    showMessage(`✗ Connection test failed to ${host}: ${error.message}`, 'error');
                } finally {
                    testBtn.disabled = false;
                    testBtn.textContent = '✓ Test Connection';
                }
            }

            addOltBtn.addEventListener('click', addOltEntry);
            addGroupBtn.addEventListener('click', addGroupEntry);
            addStackBtn.addEventListener('click', addStackEntry);

            form.addEventListener('submit', async (e) => {
                e.preventDefault();

                // Validate all hostname fields before submission
                let hasErrors = false;

                // Validate all group IDs
                const groupEntries = document.querySelectorAll('.group-entry');
                for (const entry of groupEntries) {
                    const index = entry.dataset.groupIndex;
                    const groupIdField = `group_id_${index}`;
                    if (!validateHostnameField(groupIdField, 'Group ID')) {
                        hasErrors = true;
                    }
                }

                // Validate all stack IDs
                const stackEntries = document.querySelectorAll('.stack-entry');
                for (const entry of stackEntries) {
                    const index = entry.dataset.stackIndex;
                    const stackIdField = `stack_id_${index}`;
                    if (!validateHostnameField(stackIdField, 'Stack ID')) {
                        hasErrors = true;
                    }
                }

                // Validate all OLT IDs
                const oltEntries = document.querySelectorAll('.olt-entry');
                for (const entry of oltEntries) {
                    const index = entry.dataset.oltIndex;
                    const oltIdField = `olt_id_${index}`;
                    if (!validateHostnameField(oltIdField, 'OLT ID')) {
                        hasErrors = true;
                    }
                }

                // Block submission if validation fails
                if (hasErrors || !isFormValid()) {
                    showMessage('Please fix all validation errors before submitting', 'error');
                    return;
                }

                // Collect all OLT configurations
                const olts = [];
                for (const entry of oltEntries) {
                    const index = entry.dataset.oltIndex;
                    const groupId = document.getElementById(`olt_group_${index}`).value;

                    const olt = {
                        olt_id: document.getElementById(`olt_id_${index}`).value,
                        host: document.getElementById(`host_${index}`).value,
                        username: groupId ? '' : document.getElementById(`username_${index}`).value,
                        password: groupId ? '' : document.getElementById(`password_${index}`).value,
                        stack_id: document.getElementById(`olt_stack_${index}`).value,
                        group_id: groupId
                    };
                    olts.push(olt);
                }

                if (olts.length === 0) {
                    showMessage('Please add at least one OLT configuration', 'error');
                    return;
                }

                // Collect all groups
                const groups = [];
                for (const entry of groupEntries) {
                    const index = entry.dataset.groupIndex;
                    groups.push({
                        group_id: document.getElementById(`group_id_${index}`).value,
                        username: document.getElementById(`group_username_${index}`).value,
                        password: document.getElementById(`group_password_${index}`).value,
                        suspension_profile: document.getElementById(`group_suspension_${index}`).value
                    });
                }

                // Collect all virtual stacks
                const virtual_stacks = [];
                for (const entry of stackEntries) {
                    const index = entry.dataset.stackIndex;
                    const stackId = document.getElementById(`stack_id_${index}`).value;

                    // Find OLTs assigned to this stack
                    const stackOlts = olts.filter(o => o.stack_id === stackId).map(o => o.olt_id);

                    // Find groups referenced by OLTs in this stack
                    const stackGroups = [...new Set(olts.filter(o => o.stack_id === stackId && o.group_id).map(o => o.group_id))];

                    virtual_stacks.push({
                        stack_id: stackId,
                        olt_ids: stackOlts,
                        groups: stackGroups
                    });
                }

                // Now clean up OLT objects - remove temporary fields
                olts.forEach(olt => {
                    delete olt.group_id;
                });

                submitBtn.disabled = true;
                loading.style.display = 'block';

                try {
                    const response = await fetch('/setup/save', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ olts, groups, virtual_stacks })
                    });

                    const result = await response.json();

                    if (response.ok) {
                        const oltList = result.olt_ids.join(', ');
                        const groupInfo = groups.length > 0 ? `<br><strong>Credential Groups:</strong> ${groups.length}` : '';
                        const stackInfo = virtual_stacks.length > 0 ? `<br><strong>Virtual Stacks:</strong> ${virtual_stacks.length}` : '';

                        messageArea.innerHTML = `
                            <div class="alert alert-success">
                                <strong>✓ Setup Complete!</strong><br><br>
                                <strong>Configured ${result.olt_count} OLT(s):</strong> ${oltList}${groupInfo}${stackInfo}<br><br>
                                <strong>OAuth Client Credentials:</strong><br>
                                Client ID: <code>${result.client_id}</code><br>
                                Client Secret: <code>${result.client_secret}</code><br><br>
                                <small style="color: #d32f2f; font-weight: 600;">⚠️ IMPORTANT: Save these credentials now - they won't be shown again!</small>
                                <br><br>
                                <strong>Next Steps:</strong><br>
                                📊 <a href="/docs" style="color: #003A70; text-decoration: none; font-weight: 500;">View API Documentation</a><br>
                                ✓ <a href="/validate" style="color: #003A70; text-decoration: none; font-weight: 500;">Validate Installation</a> - Run validation tests to verify your installation is working correctly<br>
                                📈 <a href="/metrics" style="color: #003A70; text-decoration: none; font-weight: 500;">View Metrics</a>
                            </div>
                        `;

                        // Scroll to top to show success message
                        window.scrollTo({ top: 0, behavior: 'smooth' });

                        // Don't auto-redirect - let user save credentials first
                        submitBtn.textContent = 'Continue to Documentation';
                        submitBtn.onclick = () => window.location.href = '/docs';
                        submitBtn.disabled = false;
                    } else {
                        showMessage(`✗ Setup failed: ${result.detail || 'Unknown error'}`, 'error');
                        submitBtn.disabled = false;
                    }
                } catch (error) {
                    showMessage(`✗ Setup failed: ${error.message}`, 'error');
                    submitBtn.disabled = false;
                } finally {
                    loading.style.display = 'none';
                }
            });

            // Add initial OLT entry on page load
            addOltEntry();

            // Add initial group and stack for convenience
            addGroupEntry();
            addStackEntry();
        </script>
    </body>
    </html>
    """

    return HTMLResponse(content=html_content)


@router.post(
    "/setup/test", include_in_schema=False, dependencies=[Depends(verify_docs_auth)]
)
async def test_olt_connection(config: OLTConfig) -> JSONResponse:
    """
    Test OLT connection and retrieve device information.

    Performs actual connection test and retrieves:
    - MSN (Machine Serial Number) from OLT
    - Device name
    - Service profiles available on the OLT
    - Confirmation that credentials work

    Used by setup wizard to validate credentials before saving and
    provide visibility into available service profiles. Auto-populates
    OLT ID field with fetched MSN for better UX.
    """
    if not is_setup_needed():
        raise HTTPException(
            status_code=403, detail="Setup is not available - already configured"
        )

    try:
        olt_id_display = config.olt_id or config.host
        logger.info(
            f"Setup wizard: Connection test requested for {olt_id_display} ({config.host})"
        )

        base_url = config.host
        if not base_url.startswith(("http://", "https://")):
            base_url = f"https://{base_url}"
        if ":" not in base_url.split("//")[1]:
            base_url = f"{base_url}:443"

        conn_info = OLTConnectionInfo(
            base_url=base_url,
            username=config.username,
            password=config.password,
            id=config.olt_id or "temp",
        )

        transport = OLTTransport(conn_info, timeout=5)
        try:
            session = Session(transport)

            device_name = session.olt.name or "Unknown"

            services = session.olt.services
            service_profiles = [
                {"id": svc.id, "name": svc.name} for svc in services[:10]
            ]

            msn = None
            try:
                device_config = transport.get_config()
                if "System" in device_config and "MSN" in device_config["System"]:
                    msn = device_config["System"]["MSN"]
                    logger.info(f"Setup wizard: Fetched MSN {msn} from {config.host}")
            except Exception as e:  # noqa: BLE001
                logger.warning(f"Setup wizard: Could not fetch MSN: {e}")

            logger.info(
                f"Setup wizard: Connection successful for {olt_id_display} - "
                f"Device: {device_name}, Services: {len(services)}, MSN: {msn or 'N/A'}"
            )

            response_data = {
                "status": "success",
                "message": "Connection successful",
                "device_name": device_name,
                "service_profiles": service_profiles,
                "total_services": len(services),
            }

            if msn:
                response_data["msn"] = msn

            return JSONResponse(content=response_data, status_code=200)

        finally:
            transport.disconnect()

    except Exception as e:  # noqa: BLE001 - API endpoint error handling
        logger.warning(
            f"Setup wizard: Connection test failed for {olt_id_display} ({config.host}): {e}"
        )
        error_msg = str(e)
        error_type = type(e).__name__

        # Provide specific, actionable error messages
        if "401" in error_msg or "Unauthorized" in error_msg or "Invalid credentials" in error_msg:
            detail = f"Authentication failed - Invalid username or password for {config.host}"
        elif "ConnectTimeout" in error_type or "timeout" in error_msg.lower() or "timed out" in error_msg.lower():
            detail = f"Connection timeout - OLT at {config.host} is not reachable. Check if the IP address is correct and the OLT is powered on and connected to the network."
        elif "ConnectionRefused" in error_type or "Connection refused" in error_msg:
            detail = f"Connection refused - OLT at {config.host} is reachable but not accepting connections on port 443. Verify the OLT management interface is enabled."
        elif "RemoteDisconnected" in error_msg or "Remote end closed" in error_msg:
            detail = f"Connection closed by OLT at {config.host} - This may indicate SSL/TLS mismatch or the OLT terminated the connection. Try checking if the OLT requires a specific protocol version."
        elif "SSLError" in error_type or "SSL" in error_msg or "certificate" in error_msg.lower():
            detail = f"SSL/TLS error connecting to {config.host} - The OLT's SSL certificate may be invalid or expired. This is common with self-signed certificates and should not prevent normal operation."
        elif "Name or service not known" in error_msg or "getaddrinfo failed" in error_msg:
            detail = f"DNS resolution failed - Cannot resolve hostname '{config.host}'. Use an IP address instead or check your DNS configuration."
        elif "Network is unreachable" in error_msg:
            detail = f"Network unreachable - Cannot reach network for {config.host}. Check your network configuration and routing."
        elif "No route to host" in error_msg:
            detail = f"No route to host - {config.host} is not reachable from this system. Check network connectivity and firewall rules."
        else:
            detail = f"Connection failed to {config.host}: {error_msg}"

        raise HTTPException(status_code=400, detail=detail) from None


@router.post(
    "/setup/save", include_in_schema=False, dependencies=[Depends(verify_docs_auth)]
)
async def save_setup_configuration(config: SetupConfig) -> JSONResponse:
    """
    Save OLT configuration(s) and generate OAuth credentials.

    Creates connections.json with provided OLT config(s) and new OAuth client.
    Only accessible when connections.json is missing or invalid.
    Supports multiple OLT configurations in a single setup.

    Validates that suspension profiles exist on all OLTs in virtual stacks.
    """
    if not is_setup_needed():
        raise HTTPException(
            status_code=403, detail="Setup is not available - already configured"
        )

    missing_profiles = await validate_suspension_profiles(config)
    if missing_profiles:
        errors = []
        for olt_id, profiles in missing_profiles.items():
            profiles_str = ", ".join(f"'{p}'" for p in profiles)
            errors.append(f"OLT '{olt_id}': missing profiles {profiles_str}")
        error_detail = (
            "Suspension profile validation failed. "
            f"The following service profiles are referenced in credential groups "
            f"but do not exist on the specified OLTs: {'; '.join(errors)}. "
            "Please ensure all suspension profiles exist on every OLT in the virtual stack "
            "before saving the configuration."
        )
        logger.warning(f"Setup wizard: Profile validation failed: {error_detail}")
        raise HTTPException(status_code=422, detail=error_detail)

    try:
        client_id = "cambium-api-client"
        client_secret = generate_oauth_client_secret()

        groups_data = [
            {
                "id": group.group_id,
                "username": group.username,
                "password": group.password,
                "suspension": {"service_profile": group.suspension_profile},
            }
            for group in config.groups
        ]

        stacks_data = [
            {
                "id": stack.stack_id,
                "olt_ids": stack.olt_ids,
                "groups": stack.groups,
            }
            for stack in config.virtual_stacks
        ]

        olts_data = []
        for olt in config.olts:
            olt_entry: dict[str, Any] = {
                "id": olt.olt_id,
                "base_url": f"https://{olt.host}",
            }

            if olt.username and olt.password:
                olt_entry["username"] = olt.username
                olt_entry["password"] = olt.password

            if olt.stack_id:
                olt_entry["stack_id"] = olt.stack_id

            olts_data.append(olt_entry)

        connections_data: dict[str, Any] = {
            "health": {
                "connection_timeout": 2,
                "retry_interval": 30,
                "success_threshold": 10,
            },
            "groups": groups_data,
            "virtual_stacks": stacks_data,
            "olts": olts_data,
            "oauth": {
                "clients": [
                    {
                        "client_id": client_id,
                        "client_secret": client_secret,
                        "enabled": True,
                    }
                ]
            },
        }

        connections_path = get_connections_path()
        connections_path.parent.mkdir(parents=True, exist_ok=True)

        with open(connections_path, "w") as f:
            json.dump(connections_data, f, indent=2)

        olt_ids = [olt.olt_id for olt in config.olts]
        logger.info(
            f"Setup wizard: Configuration saved successfully for {len(olt_ids)} OLT(s): {', '.join(olt_ids)}"
        )

        return JSONResponse(
            content={
                "status": "success",
                "message": "Configuration saved successfully",
                "client_id": client_id,
                "client_secret": client_secret,
                "olt_count": len(config.olts),
                "olt_ids": olt_ids,
            },
            status_code=200,
        )

    except Exception as e:  # noqa: BLE001 - API endpoint error handling
        logger.error(f"Setup wizard: Failed to save configuration: {e}")
        raise HTTPException(
            status_code=500, detail=f"Failed to save configuration: {e!s}"
        ) from None
