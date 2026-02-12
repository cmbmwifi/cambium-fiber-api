# Changelog

All notable changes to the OLT REST API will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

---

## [1.0.0-beta.1] - 2026-02-11

### Added
- **Setup wizard authentication protection** - HTTP Basic Auth now protects /setup endpoints (/setup, /setup/test, /setup/save) using the same docs_auth credentials system
- **Documentation header navigation** - "Cambium Fiber API" title and settings gear icon in Swagger UI header enables quick navigation to /setup from documentation

### Fixed
- **Installer false positive success reports** - Installer now validates all critical endpoints (/health, /docs, /setup) before declaring success
  - Added comprehensive endpoint validation with retry logic
  - Added detailed troubleshooting guidance when endpoints fail
  - Added container log display on failures
  - Success message now only shows verified endpoints with ✓ indicators
  - Exit with error code if any critical endpoint fails validation
  - Applies to both Linux (install.sh) and Windows (install.ps1) installers
- **Added installer validation tests** - 10+ new tests ensure installers properly validate endpoints and provide troubleshooting guidance
- **FastAPI dependency injection compatibility** - Fixed `verify_docs_auth()` function signature for Python 3.13 + FastAPI (keyword-only parameter)

### Changed
- **Simplified installer output** - Reduced verbose installation messages to focus on actionable next steps
  - Success message now clearly highlights: "Open http://localhost:8000/setup to configure your OLTs"
  - Removed technical details (container status, verified endpoints list, common commands)
  - Quieter validation output - shows dots during health check wait, then "✓ Ready"
  - Removed browser opening messages in headless mode
  - Makes it immediately clear what the user should do after installation completes
- **Docker image optimization** - Reduced production image from 1.72GB to 440MB (74% smaller) using multi-stage build
  - Build stage contains compilation tools (gcc, g++, cargo)
  - Production stage contains only runtime dependencies
  - Tarball reduced from 434MB to 113MB
  - No functional changes, pure size optimization

---

## [1.0.0] - 2026-02-04

### Added
- OAuth 2.0 authentication with JWT tokens (RFC 6749 Client Credentials flow)
- Rate limiting on OAuth token endpoint (10 requests/minute)
- Dual API versioning (v1 legacy + v2 RESTful)
- ONU pre-provisioning and automatic discovery (configure ONUs before connection, auto-detect when plugged in, track configuration drift)
- OLT health tracking with fast-fail on offline devices
- File-based configuration caching (30s TTL, atomic locking)
- SSH backup/restore for OLT configurations
- Structured logging with runtime log level API
- ETag caching (RFC 7232 conditional requests)
- Error handling with i18n support (27 messages, 5 languages)
- Production Docker image with non-root user
- Comprehensive documentation (17 architecture guides)
- OAuth client management CLI (`scripts/manage_oauth_clients.py`)
- Mock OLT infrastructure for testing (6 containers)
- Apache 2.0 license

### Security
- SSL/TLS verification disabled for OLT connections by design (hardware constraint)
  - **Mitigation required:** Deploy OLTs on isolated management network (RFC1918/CGNAT)
  - See [pub/SECURITY.md](pub/SECURITY.md) for detailed guidance
- Self-signed certificate detection with startup warnings for public IP deployments
- Rate limiting prevents brute force attacks on authentication endpoint
- SHA-256 hashed OAuth client secrets
- Input validation via Pydantic models
- SQL injection protection with parameterized queries

### Testing
- 494 passing tests (445 unit + 49 integration)
- BDD/Gherkin feature tests
- Real OLT compatibility testing
- Pre-commit git hooks enforce quality gates
- Zero lint errors (ruff, pyright, YAML, markdown)

### Documentation
- [pub/INSTALL.md](pub/INSTALL.md) - Production installation guide
- [pub/SECURITY.md](pub/SECURITY.md) - Security architecture and best practices
- [pub/UPGRADE_GUIDE.md](pub/UPGRADE_GUIDE.md) - Version upgrade procedures
- [pub/MONITORING.md](pub/MONITORING.md) - Logging and observability
- API documentation via Swagger UI (`/docs`) and ReDoc (`/redoc`)

### Known Limitations
- Webhook endpoint (`/webhook`) exposed but feature disabled by default
  - Set `ENABLE_WEBHOOKS=true` to enable (not production-ready in v1.0.0)
- Prometheus metrics endpoint not yet implemented
- API v1 endpoints deprecated (will be removed in a future major version)

### Breaking Changes
- OAuth 2.0 authentication now required for all endpoints (no anonymous access)
- API v1 endpoints return `X-API-Version-Deprecated` header

### Upgrade Notes
- First stable release - no upgrade path from pre-release versions
- Create `oauth_clients.json` for authentication
- Update client applications to obtain OAuth tokens before API requests
- Migrate from `/api/v1` to `/api/v2` endpoints (v1 deprecated)

---

## Release Notes Format

Each release includes:
- **Added:** New features
- **Changed:** Changes in existing functionality
- **Deprecated:** Soon-to-be removed features
- **Removed:** Removed features
- **Fixed:** Bug fixes
- **Security:** Security fixes/improvements

---

**Note:** See [pub/UPGRADE_GUIDE.md](pub/UPGRADE_GUIDE.md) for detailed upgrade instructions between versions.
