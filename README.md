# Cambium Fiber API

RESTful API for managing Cambium Fiber OLT and ONU devices. Compatible with cnMaestro API patterns.

## Quick Start with Automated Installer

**Prerequisites:** Docker Desktop installed from https://docker.com/products/docker-desktop

### Linux / macOS

Run the installer with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/cambiumnetworks/cambium-fiber-api/main/install.sh | bash
```

The installer will:
- ✓ Check Docker installation
- ✓ Download and start the API container
- ✓ Open the setup wizard in your browser
- ✓ Guide you through OLT configuration

### Windows

Run in PowerShell:

```powershell
Invoke-WebRequest -Uri https://raw.githubusercontent.com/cambiumnetworks/cambium-fiber-api/main/install.ps1 -OutFile install.ps1; .\install.ps1
```

The installer will:
- ✓ Check Docker installation
- ✓ Download and start the API container
- ✓ Open the setup wizard in your browser
- ✓ Guide you through OLT configuration

> **Alternative:** If you prefer to review the installer script first, clone the repository and run `./install.sh` or `.\install.ps1` locally. The scripts work identically whether downloaded via curl or run from a local checkout.

### After Installation

1. **Complete the web setup wizard** - Configure your OLT connections through the browser interface
2. **Save your OAuth credentials** - Generated during setup, needed for API authentication
3. **Access the API docs** - Visit http://localhost:8000/docs for interactive documentation

Installation directory: `/opt/cambium-fiber-api` (Linux/Mac) or `%LOCALAPPDATA%\Cambium\cambium-fiber-api` (Windows)

---

## Validating Your Installation

After installation, verify that your deployment is working correctly with the built-in validation tool.

### Quick Start

Open your browser and navigate to:

```
http://localhost:8000/validate
```

Or for remote installations:

```
http://your-server-address:8000/validate
```

### What Gets Tested

The validation tool runs comprehensive checks:
- **Health Endpoints** - API availability and metrics
- **Authentication** - OAuth token flow and permissions
- **OLT Management** - Device connectivity and status
- **ONU Operations** - Read operations and device discovery
- **Profile Management** - Configuration validation
- **Service Profiles** - VLAN and port configuration

### Safety Guarantees

✅ **Production Safe** - All tests use:
- Read-only operations (GET requests)
- Dry-run mode for write operations (no actual changes)
- Safe for running against live production systems

### When to Run Validation

- **After fresh installation** - Verify everything works
- **After version upgrades** - Confirm functionality after updates
- **Troubleshooting issues** - Identify configuration or connectivity problems
- **Before going live** - Final pre-production check

### Detailed Documentation

For comprehensive information about validation testing, interpreting results, and troubleshooting common issues, see [VALIDATION.md](VALIDATION.md).

---

## Uninstallation

### Linux / macOS

```bash
bash uninstall.sh
```

### Windows

```powershell
.\uninstall.ps1
```

The uninstaller will:
- Stop and remove the container
- Prompt to remove Docker image (optional)
- Prompt to remove data directory (optional)
- Docker Desktop remains unaffected

---

## Common Commands

```bash
# Start the API
cd /opt/cambium-fiber-api
docker-compose up -d

# Stop the API
cd /opt/cambium-fiber-api
docker-compose down

# View logs
docker logs -f cambium-fiber-api

# Check status
docker ps | grep cambium-fiber-api
```

## Documentation & Support

- **API Documentation:** http://localhost:8000/docs (interactive Swagger UI)
- **Support:** support@cambiumnetworks.com

Apache License 2.0 - See [LICENSE](LICENSE)
