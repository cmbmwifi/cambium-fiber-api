# Changelog

All notable changes to the OLT REST API will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---


## [1.0.0-RC6] - 2026-04-16

- **Delete ONU**: new `DELETE /api/v2/fiber/onus/{serial}` and `DELETE /api/v2/fiber/olts/{olt_id}/onus/{serial}` endpoints to remove an ONU from the OLT (it will re-onboard automatically with default settings)
- **List all pre-provisioned configs**: new `GET /api/v2/fiber/onus/pending-configs` endpoint returns all stored pre-provisioning configurations
- Clarified pre-provisioning documentation — endpoint summaries now explain that pending configs are applied when an ONU first onboards
- Linux installer auto-installs Docker Engine via `get.docker.com` when Docker is missing (with user prompt); improved error messages for headless servers

## [1.0.0-RC5] - 2026-04-13

- PowerShell installer/uninstaller: native Windows Forms GUI (single wizard form, no external modules)
- Linux installer/uninstaller: whiptail/dialog TUI with plain-text fallback
- Docker Desktop auto-detection and startup prompt on Windows

## [1.0.0-RC4] - 2026-03-30

- Official support for Python 3.13
- Improved installation and upgrade reliability
- Better version and environment management
- General stability improvements

### Build & Deployment
- Dockerfile optimizations: moved ARG VERSION, improved build caching
- Docker Compose: force-recreate for env reload, dropped obsolete version field
- Auto-derive version from git tag, sync APP_VERSION across container and environment
- Fixed VERSION/COMPOSE_PROJECT_NAME handling in build flow

### Install & Scripts
- Improved install scripts for reliability and environment consistency
- Miscellaneous fixes to Makefile and integration test scripts

---

## [1.0.0-RC3] - 2026-03-18

- More reliable installation process
- Easier to use release packages
- Improved test coverage and simulation
- Minor documentation and config updates

### Install & Release
- Fix install script terminal hang by using per-read /dev/tty redirects
- Re-tag loaded Docker image to CAMBIUM_API_IMAGE after download
- Resolve 'latest' version via GitHub API, fix installer URL case normalization
- Lowercase version in __version__.py, use GitHub Releases for tarball

### Developer Experience
- Added IDEAS.md for future improvements
- Limited commit hook to olt-rest-api directory

### Test Infrastructure
- Replaced FixtureTransport with mock OLT containers for integration tests
- Added fast_reply marker and static IPs to docker-compose
- Various test and config updates

## [1.0.0-RC2] - 2026-03-11

### Polish, Observability, & Error Handling
- HTTP access logging with request IDs and latency
- Sensitive data masking in logs
- SSH error classification with actionable messages
- Rate limiting on credentials download endpoint
- Build timestamp in setup wizard footer
- Improved JSON validation error handling
- Enforced read-only OAuth clients across all PUT/PATCH routes with localized insufficient-scope errors

## [1.0.0-RC1] - 2026-03-09

Initial release candidate.

Unified REST API for managing fiber networks across multiple OLTs. Reduces operational complexity by centralizing ONU provisioning, location tracking, and configuration management into a single interface.

### Operational Efficiency
- **Zero-touch ONU deployment** - Pre-configure ONUs before installation; settings apply automatically when plugged in
- **Network-wide ONU location tracking** - Auto-resolve OLT for ONUs simplifying API Integrations
- **Automated OLT health monitoring** - Real-time status checks prevent operations on offline devices
- **One-click configuration backup and restore** - Protect against configuration loss and enable rapid disaster recovery

### Scale and Integration
- **Multi-OLT aggregation** - Manage hundreds of ONUs across multiple OLTs through single API endpoint
- **Standards-based authentication** - OAuth 2.0 with JWT tokens for secure system-to-system integration
- **RESTful API design** - Modern HTTP-based interface integrates with OSS/BSS platforms and automation tools
- **Secure by default** - Rate limiting, hashed credentials, and input validation built-in

### Deployment and Operations
- **Web-based setup wizard** - Configure OLT connections through browser interface, no command-line required
- **One-command installation** - Docker-based deployment with automated installers for Linux and Windows
- **Multi-language support** - Error messages in English, Spanish, Russian, Chinese, and Hindi
- **Apache 2.0 license** - Open source with commercial-friendly licensing

### Deployment Requirements
- **Designed for private management networks** - Deploy on isolated RFC1918/CGNAT networks for OLT communication
- See [SECURITY.md](SECURITY.md) for network architecture guidance and best practices
