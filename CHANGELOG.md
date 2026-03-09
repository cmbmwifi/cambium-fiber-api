# Changelog

All notable changes to the OLT REST API will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

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
