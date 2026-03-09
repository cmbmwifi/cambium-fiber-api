# Installation Validation Guide

This guide explains how to validate your Cambium Fiber API installation using the built-in web-based validation tool.

## Purpose

The validation tool helps you:

- ✅ **Verify Installation** - Confirm API is properly configured and accessible after deployment
- ✅ **Troubleshoot Issues** - Quickly identify connectivity, authentication, or configuration problems
- ✅ **Validate Upgrades** - Ensure the system continues working correctly after version updates
- ✅ **Build Confidence** - Comprehensive testing builds trust in production deployments

## Accessing the Validation Tool

After installation, open the validation interface in your web browser:

```
http://your-server:8192/validate
```

**Finding the Link:**
- From the **setup wizard completion screen** - Click "✓ Validate Installation"
- From the **API documentation** - Navigate from http://your-server:8192/docs
- **Bookmark it** - Useful for periodic health checks

Replace `your-server` with:
- `localhost` if running on the same machine
- Your server's hostname or IP address if accessing remotely

## What's Tested

All validation tests use **production-safe operations**:

### Test Categories

| Category | Description | Operations |
|----------|-------------|------------|
| **Health** | System health and metrics endpoints | GET /health, GET /metrics |
| **Authentication** | OAuth 2.0 token flow and rate limiting | POST /oauth/token |
| **OLTs** | OLT management operations | GET /api/v2/fiber/olts |
| **ONUs** | ONU read/write operations | GET/PATCH /api/v2/fiber/onus (with dry-run) |
| **Profiles** | ONU Profile management | GET/POST/PATCH /api/v2/fiber/olts/{id}/profiles (with dry-run) |
| **Services** | Service Profile management | GET/POST/PATCH /api/v2/fiber/olts/{id}/services (with dry-run) |

**Safety Guarantees:**
- ✅ All read operations (GET) only retrieve data - never modify your OLT configuration
- ✅ All write operations (POST/PATCH/DELETE) use **dry-run mode** (`?dry_run=true`)
  - Validates request logic and format
  - Returns execution plan showing what WOULD be done
  - **Does NOT send commands to OLT hardware**
- ✅ No data deletion or destructive operations

You can safely run these tests in production without risk of modifying your OLT configuration.

## Running Validation Tests

### Step-by-Step

1. **Open the validation page** - http://your-server:8192/validate

2. **Select test categories** - Check the boxes for categories you want to test:
   - Select all categories for comprehensive validation
   - Select specific categories to troubleshoot particular issues

3. **Click "Run Validation Tests"** - The button starts the validation process

4. **Wait for completion** - You'll see:
   - "Running..." spinner while tests execute
   - Progress updates as tests complete
   - Typical duration: 10-30 seconds for all categories

5. **Review results** - See detailed results organized by category

### Quick Validation (Recommended After Installation)

For initial validation after installation, select **all categories** to ensure complete system functionality.

### Targeted Testing (Troubleshooting)

If experiencing specific issues:
- **API not responding?** → Test only **Health** category
- **Authentication failures?** → Test only **Authentication** category
- **ONU operations failing?** → Test **ONUs** category
- **Profile problems?** → Test **Profiles** and **Services** categories

## Interpreting Results

### Understanding the Display

The validation interface shows test results with color-coded indicators:

#### ✅ **Green (Passed)**
```
✅ Health check endpoint responds with status OK
```
- **Meaning:** Test passed successfully
- **Action:** No action needed - this component is working correctly

#### ❌ **Red (Failed)**
```
❌ OAuth token acquisition with valid credentials should succeed
    └─ Error: 401 Unauthorized - Invalid credentials
    └─ Details: Click to expand full error message
```
- **Meaning:** Test failed - indicates a problem
- **Action:** Click to expand error details, see "Common Failures" section below
- **Impact:** This feature is not working, needs attention

#### ⏭️ **Yellow (Skipped)**
```
⏭️ Update ONU profile with dry-run mode
    └─ Reason: No ONUs available for testing
```
- **Meaning:** Test skipped because prerequisites weren't met
- **Action:** Usually safe to ignore - test couldn't run due to missing resources
- **Examples:** No ONUs configured, no profiles exist, etc.

### Summary Statistics

At the top of results, you'll see:
```
Tests: 35/38 passed (92%)
Duration: 12.4 seconds
Timestamp: 2026-02-09 14:23:15 UTC
```

- **Passed percentage** - Overall success rate
- **Duration** - How long tests took to run
- **Timestamp** - When tests were executed

### Ideal Results

A healthy installation should show:
- ✅ All **Health** tests passed
- ✅ All **Authentication** tests passed
- ✅ All **OLTs** tests passed
- ✅ Most **ONUs/Profiles/Services** tests passed (some may skip if no resources configured)

## Common Failures and Solutions

### Authentication Failures

#### ❌ OAuth token acquisition failed: 401 Unauthorized

**Cause:** Invalid or missing OAuth credentials

**Solutions:**
1. Open your `connections.json` file
2. Find the `oauth_clients` section
3. Verify the client_id and client_secret match what you configured during setup
4. Ensure the OAuth client has required scopes:
   - Minimum: `read:olts`, `read:onus`, `read:profiles`, `read:services`
   - Recommended: Add `write:*` scopes for dry-run write tests

**Example connections.json:**
```json
{
  "oauth_clients": [
    {
      "client_id": "your_client_id",
      "client_secret": "your_secret_here",
      "scopes": ["read:olts", "read:onus", "write:onus"]
    }
  ]
}
```

After fixing credentials, restart the API:
```bash
cd /opt/cambium-fiber-api
docker-compose restart
```

### OLT Communication Failures

#### ❌ 502 Bad Gateway - OLT communication failed

**Cause:** API cannot reach the OLT device

**Solutions:**
1. **Check OLT is powered on** - Verify the physical device has power
2. **Test network connectivity** from the API server:
   ```bash
   ping <olt-ip-address>
   ```
3. **Check firewall rules:**
   - OLT must allow SSH connections from API server (port 22)
   - Check both API server outbound rules and OLT firewall
4. **Verify routing:**
   - Ensure network path exists between API server and OLT
   - Check VLANs, subnets, routing tables
5. **Check OLT credentials** in connections.json:
   ```json
   {
     "OLTs": {
       "F6ZF01C8P631": {
         "host": "192.168.1.10",
         "username": "admin",
         "password": "your_password"
       }
     }
   }
   ```

### Configuration Validation Errors

#### ❌ Dry-run validation failed: Invalid profile parameters

**Cause:** Request parameters don't meet validation rules

**Solutions:**
1. **Review error details** - Expand the error to see specific validation messages
2. **Common issues:**
   - Profile name contains invalid characters (use alphanumeric and underscore only)
   - VLAN IDs out of range (must be 1-4094)
   - Speed values invalid (check supported speeds for your OLT model)
   - Missing required fields in request
3. **Test with API documentation:**
   - Visit http://your-server:8192/docs
   - Use interactive "Try it out" to test parameters
   - Review schema definitions for valid values

### Network and Connectivity

#### ❌ Connection refused or timeout errors

**Cause:** Cannot reach API server

**Solutions:**
1. **Verify API is running:**
   ```bash
   docker ps | grep cambium-fiber-api
   ```
   Should show container status as "Up"

2. **Check API health directly:**
   ```bash
   curl http://localhost:8192/health
   ```
   Should return: `{"status": "ok"}`

3. **Review firewall rules:**
   - API port (default 8192) must be open
   - Check iptables, firewalld, or cloud security groups
   - Test from another machine: `telnet your-server 8192`

4. **Check Docker networking:**
   ```bash
   docker logs cambium-fiber-api
   ```
   Look for startup errors or port binding issues

## Exporting Results

### Download JSON Report

Click the **"Export Results"** button to download a JSON file containing:
- All test outcomes (passed/failed/skipped)
- Execution duration per test
- Detailed error messages and stack traces
- Summary statistics

### Use Cases

- **Support tickets** - Attach validation-report.json when contacting support
- **Documentation** - Keep records of validation after upgrades
- **Compliance** - Maintain audit trail of system health checks
- **Automation** - Parse JSON for automated monitoring systems

### Example Report Structure

```json
{
  "summary": {
    "passed": 35,
    "failed": 2,
    "skipped": 1,
    "total": 38,
    "duration": 12.4
  },
  "tests": [
    {
      "name": "Health check endpoint responds",
      "outcome": "passed",
      "duration": 0.123
    },
    {
      "name": "OAuth token acquisition",
      "outcome": "failed",
      "duration": 1.456,
      "error": "401 Unauthorized - Invalid credentials"
    }
  ]
}
```

## When to Run Validation Tests

### Required Scenarios

Run validation tests in these situations:

- ✅ **After fresh installation** - Verify setup completed successfully before production use
- ✅ **After version upgrades** - Confirm new version works correctly, no regressions
- ✅ **Before production cutover** - Final confidence check before going live
- ✅ **When troubleshooting** - Identify specific components causing issues

### Optional Scenarios

Consider periodic validation for ongoing operations:

- 🔄 **Weekly/monthly health checks** - Proactive monitoring of production system
- 🔄 **After configuration changes** - Verify changes didn't break API functionality
- 🔄 **After network changes** - Confirm routing and firewall rules still work
- 🔄 **After adding new OLTs** - Validate new devices are accessible

### Recommended Schedule

For production deployments:
- **Immediately** after installation
- **Always** after upgrades (before production traffic)
- **Monthly** for proactive health monitoring
- **As needed** when troubleshooting issues

## Security and Safety

### Production-Safe Operations

The validation tool is designed to be **100% safe** for production environments:

1. **Read-only operations:**
   - GET requests only retrieve existing data
   - No modifications to OLT configuration
   - No changes to ONU states or profiles

2. **Dry-run mode for writes:**
   - All PATCH/POST/DELETE operations include `?dry_run=true`
   - API validates request format and logic
   - Returns execution plan without sending commands to OLT
   - You see what WOULD happen, but nothing actually changes

3. **No destructive operations:**
   - No DELETE operations executed (only tested in dry-run)
   - No ONU deactivations or profile removals
   - No configuration erasure

4. **Rate limiting respected:**
   - Tests verify rate limiting works (429 responses expected)
   - Won't overwhelm your OAuth token endpoint
   - Standard timeouts prevent hanging requests

### Authentication Required

Validation tests use **the same OAuth authentication** as production API clients:
- Tests acquire real OAuth tokens from your configured credentials
- Validates that authentication flow works end-to-end
- Tests respect the same authorization scopes as production

### Data Privacy

- Validation runs locally on your API server
- No data transmitted to external services
- Results stored temporarily in memory
- Export JSON contains only test outcomes (no sensitive OLT credentials)

## Troubleshooting the Validation Tool

### Validation page won't load

**Problem:** http://your-server:8192/validate returns error

**Solutions:**
1. Verify API is running: `docker ps | grep cambium-fiber-api`
2. Check API health: `curl http://your-server:8192/health`
3. Review API logs: `docker logs cambium-fiber-api`
4. Ensure you're using the correct hostname/IP and port

### Tests stuck on "Running..."

**Problem:** Tests run indefinitely without completing

**Solutions:**
1. **Refresh the page** - May have lost connection to API
2. **Check API responsiveness:**
   ```bash
   curl http://your-server:8192/health
   ```
3. **Review logs for errors:**
   ```bash
   docker logs -f cambium-fiber-api
   ```
4. **Restart API if frozen:**
   ```bash
   docker-compose restart
   ```

### All tests fail immediately

**Problem:** Every test shows red X immediately

**Likely causes:**
1. **OAuth credentials invalid** - Most common issue
   - Fix: Update connections.json with valid client_id/client_secret
   - Restart API after changes

2. **No OLTs configured** - Nothing to test
   - Fix: Run setup wizard to configure at least one OLT
   - Or manually edit connections.json to add OLTs

3. **OLT unreachable** - Network connectivity issue
   - Fix: Verify network routing, firewall rules, OLT powered on

### Persistent failures after fixes

**Problem:** Fixed configuration but tests still fail

**Solution:**
1. **Restart the API** to pick up configuration changes:
   ```bash
   cd /opt/cambium-fiber-api
   docker-compose restart
   ```

2. **Clear browser cache** - Old results may be cached

3. **Wait 30 seconds** - Configuration cache has 30s TTL

4. **Review logs** for detailed error messages:
   ```bash
   docker logs -f cambium-fiber-api | grep ERROR
   ```

## Advanced: Command-Line Testing

For automation or CI/CD integration, you can run validation tests from the command line:

```bash
# Navigate to tests directory
cd /opt/cambium-fiber-api/pub/tests

# Set environment variables
export OAUTH_CLIENT_ID="your_client_id"
export OAUTH_CLIENT_SECRET="your_secret"
export API_BASE_URL="http://localhost:8192"

# Run all tests
pytest

# Run specific category
pytest -m health
pytest -m auth
pytest -m onus

# Generate JSON report
pytest --json-report --json-report-file=validation-report.json
```

See `pub/tests/README.md` for complete command-line documentation.

## Getting Help

If validation reveals issues you cannot resolve:

1. **Review error messages carefully** - Most failures include specific solutions
2. **Check the FAQ** - Common issues documented above
3. **Export results** - Download JSON report for support tickets
4. **Review logs** - API logs contain detailed error traces
5. **Contact support** - support@cambiumnetworks.com with:
   - Exported validation JSON report
   - API version (visible in UI or logs)
   - Description of when failures started (after upgrade? fresh install?)

## Additional Documentation

- **Installation Guide:** `README.md` - Initial setup instructions
- **API Documentation:** http://your-server:8192/docs - Interactive API reference
- **Test Details:** `pub/tests/README.md` - Command-line testing documentation
- **Architecture:** `docs/architecture/production-validation.md` - Design decisions

---

**Remember:** Validation tests are safe to run anytime. They use read-only operations and dry-run mode to verify functionality without modifying your production OLT configuration.
