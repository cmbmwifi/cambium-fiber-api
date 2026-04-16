# Cambium Fiber API

Unified REST API for managing fiber networks across multiple OLTs. Pre-configure ONUs before deployment, track devices network-wide, and integrate with OSS/BSS platforms through a single endpoint.

**For:** ISPs, MSPs, and system integrators managing Cambium Fiber networks

## 📖 API Documentation

**[View Interactive API Documentation](https://cmbmwifi.github.io/cambium-fiber-api/)** — Browse all endpoints, request/response schemas, and authentication flows before installing.

## Key Capabilities

- **Multi-OLT aggregation** - Control hundreds of ONUs across all OLTs through one API
- **Zero-touch ONU deployment** - Pre-configure settings that apply automatically when devices connect
- **Network-wide location tracking** - Instantly locate any ONU across your entire fiber infrastructure
- **Standards-based integration** - OAuth 2.0 authentication for secure system-to-system connections
- **One-command installation** - Docker-based deployment, running in minutes

## Quick Start

**Prerequisites:** [Docker](https://docs.docker.com/engine/install/) or [Docker Desktop](https://docker.com/products/docker-desktop) installed (the Linux installer will offer to install Docker Engine automatically if missing)

### Linux / macOS

```bash
curl -fsSL https://raw.githubusercontent.com/cmbmwifi/cambium-fiber-api/refs/heads/main/install.sh | bash
```

### Windows (PowerShell 7.x)

```powershell
Invoke-WebRequest -Uri https://raw.githubusercontent.com/cmbmwifi/cambium-fiber-api/refs/heads/main/install.ps1 -OutFile install.ps1; .\install.ps1
```

### Installation Process Overview

1. **Run the installer** using the command above
2. **Complete setup** at http://localhost:8192/setup (installer will prompt you)
3. **Start using the API** - Explore interactive docs at http://localhost:8192/docs or integrate with your OSS/BSS platform

## Validation & Testing

Verify your installation is working correctly:

```
http://localhost:8192/validate
```

Runs read-only tests against health endpoints, authentication, OLT connectivity, and ONU operations. Safe for production systems. See [VALIDATION.md](VALIDATION.md) for details.

## API Development With Mock OLTs

For hardware-free API development, demos, and CI workflows, use the standalone mock OLT repository:

**https://github.com/cmbmwifi/cambium-fiber-mock-olt**

That repository provides containerized mock Cambium Fiber OLTs with editable fixture files so you can control the starting device state for local development and integration testing.

## Managing the API

```bash
# View logs
docker logs -f cambium-fiber-api

# Stop/Start
cd /opt/cambium-fiber-api  # or %ProgramData%\Cambium\cambium-fiber-api on Windows
docker-compose down
docker-compose up -d

# Uninstall
bash uninstall.sh  # or .\uninstall.ps1 on Windows
```

---

**Documentation:** http://localhost:8192/docs • **Support:** support@cambiumnetworks.com • **License:** Apache 2.0
