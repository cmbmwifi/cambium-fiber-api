# Production Validation Tests

This directory contains production-safe validation tests for the Cambium Fiber API. These tests are designed to run against deployed API instances to verify functionality, troubleshoot issues, and validate upgrades.

## Purpose

- **Verify Installation**: Confirm API is properly configured and accessible after deployment
- **Troubleshoot Issues**: Identify connectivity, authentication, or configuration problems
- **Validate Upgrades**: Ensure system continues working correctly after version updates
- **Build Confidence**: Comprehensive testing builds trust in production deployments

## What's Tested

All tests use **production-safe operations**:

- ✅ **Read-only operations**: GET requests that don't modify OLT configuration
- ✅ **Dry-run mode**: Write operations with `?dry_run=true` validate logic without changing OLTs
- ✅ **OAuth authentication**: Real token acquisition and authorization flow
- ✅ **Rate limiting**: API protection mechanisms

### Test Coverage

1. **health.feature** - Health check and Prometheus metrics endpoints
2. **authentication.feature** - OAuth 2.0 token acquisition, scope validation, rate limiting
3. **olts.feature** - List OLT IDs, verify cnMaestro array response format
4. **onus_read.feature** - All ONU GET endpoints (list, get by serial, pagination, filtering)
5. **onus_write.feature** - ONU PATCH operations with dry_run=true (single, bulk)
6. **profiles.feature** - ONU Profile endpoints (list, get, CRUD with dry_run)
7. **services.feature** - Service Profile endpoints (list, get, CRUD with dry_run)

## Requirements

### System Requirements

- Python 3.11+ with pytest and pytest-bdd installed
- Network connectivity to deployed API instance
- OAuth client credentials (client_id and client_secret)

### Environment Variables

Create a `.env` file or export these variables:

```bash
# Required: OAuth credentials from connections.json
export OAUTH_CLIENT_ID="your_client_id_here"
export OAUTH_CLIENT_SECRET="your_client_secret_here"

# Optional: API base URL (defaults to localhost)
export API_BASE_URL="http://your-server:8192"
```

**Finding OAuth Credentials:**

1. Open your `connections.json` configuration file
2. Look for the `oauth_clients` section
3. Use credentials for a client with appropriate scopes:
   - Minimum: `read:olts`, `read:onus`, `read:profiles`, `read:services`
   - Recommended: Add `write:*` scopes to test dry-run write operations

Example `connections.json` excerpt:
```json
{
  "oauth_clients": [
    {
      "client_id": "validator_client",
      "client_secret": "your_secret_here",
      "scopes": ["read:olts", "read:onus", "write:onus", "read:profiles", "write:profiles"]
    }
  ]
}
```

## Running Tests

### Run All Tests

```bash
cd pub/tests
pytest
```

### Run Specific Test Category

```bash
# Test only health endpoints
pytest -m health

# Test only authentication
pytest -m auth

# Test only ONU operations
pytest -m onus

# Test only read-only operations
pytest -m read_only

# Test only dry-run write operations
pytest -m dry_run
```

### Run Specific Feature File

```bash
# Test health and metrics
pytest features/health.feature

# Test authentication
pytest features/authentication.feature

# Test ONU read operations
pytest features/onus_read.feature
```

### Verbose Output

```bash
# Show detailed test output
pytest -v

# Show print statements and full error traces
pytest -v -s
```

### Stop on First Failure

```bash
# Stop immediately when a test fails
pytest -x
```

## Interpreting Results

### Successful Test Run

```
features/health.feature::test_health_check PASSED                   [ 10%]
features/authentication.feature::test_oauth_token PASSED            [ 20%]
features/olts.feature::test_list_olts PASSED                        [ 30%]
...
========================== 35 passed in 12.34s ==========================
```

All tests passed - your installation is working correctly!

### Failed Tests

```
features/authentication.feature::test_oauth_token FAILED            [ 20%]
...
E   AssertionError: OAuth token acquisition failed: 401 - {"detail": "Invalid credentials"}
```

**Common Failures and Fixes:**

| Failure Pattern | Likely Cause | Solution |
|----------------|-------------|----------|
| `OAuth token acquisition failed: 401` | Invalid credentials | Verify `OAUTH_CLIENT_ID` and `OAUTH_CLIENT_SECRET` match `connections.json` |
| `API not accessible` | Network/firewall issue | Check API is running: `curl http://your-server:8192/health` |
| `No OLTs configured` | Empty configuration | Verify `connections.json` has `OLTs` section with at least one OLT |
| `502 Bad gateway - OLT communication` | OLT unreachable | Check network routing, firewall rules, OLT powered on |
| `404 Not found` | Incorrect API_BASE_URL | Verify base URL format: `http://hostname:port` (no trailing slash) |
| `429 Too Many Requests` | Rate limiting active | Wait 1 minute and retry (normal behavior for rate limit tests) |

### Skipped Tests

```
features/profiles.feature::test_create_profile SKIPPED              [ 80%]
...
s   Reason: No profiles on OLT F6ZF01C8P631
```

Tests skipped because required resources didn't exist (e.g., no profiles to test). This is normal if your OLT configuration is minimal. Skipped tests don't indicate problems.

## Test Output Artifacts

### JSON Report (if pytest-json-report installed)

```bash
pytest --json-report --json-report-file=validation-report.json
```

Generates machine-readable JSON report with:
- Test outcomes (passed/failed/skipped)
- Execution duration per test
- Error details and stack traces
- Summary statistics

Useful for:
- Support tickets (attach validation-report.json)
- Automated monitoring
- Historical trend analysis

### HTML Report (if pytest-html installed)

```bash
pytest --html=validation-report.html --self-contained-html
```

Generates visual HTML report with color-coded results and expandable error details.

## Safety Guarantees

These tests are **safe to run in production** because:

1. **Read-only operations**: GET requests only retrieve data, never modify OLT configuration
2. **Dry-run mode**: Write operations (PATCH/POST/DELETE) use `?dry_run=true` parameter
   - Validates request logic and serialization
   - Returns execution plan showing what WOULD be done
   - Does NOT send commands to OLT hardware
3. **No data deletion**: DELETE operations only tested in dry-run mode
4. **OAuth rate limiting**: Tests verify rate limiting protects against abuse
5. **Standard timeouts**: Requests timeout after 10 seconds to prevent hanging

## When to Run These Tests

### Required Scenarios

- ✅ **After fresh installation** - Verify setup completed successfully
- ✅ **After version upgrades** - Confirm compatibility and no regressions
- ✅ **Before production cutover** - Final validation before going live
- ✅ **When troubleshooting** - Identify connectivity or configuration issues

### Optional Scenarios

- 🔄 **Periodic health checks** - Weekly/monthly validation of production system
- 🔄 **After configuration changes** - Verify changes didn't break API functionality
- 🔄 **After network changes** - Confirm routing and firewall rules still work

## Troubleshooting Test Execution

### ImportError: No module named 'pytest_bdd'

```bash
pip install pytest pytest-bdd requests python-dotenv
```

### Tests hang or timeout

- Verify `API_BASE_URL` is correct and API is running
- Check firewall rules allow access to API port
- Confirm network connectivity: `ping your-server` and `curl http://your-server:8192/health`

### Connection refused errors

- API server not running: Start with `docker-compose up -d`
- Wrong port: Verify API_BASE_URL port matches docker-compose configuration
- Firewall blocking: Check iptables/firewalld rules allow API port

### All tests fail with 401 Unauthorized

- OAuth credentials missing or incorrect
- Check `.env` file exists and has correct `OAUTH_CLIENT_ID` / `OAUTH_CLIENT_SECRET`
- Verify credentials exist in `connections.json` oauth_clients section
- Confirm client scopes include: `read:olts`, `read:onus`, `read:profiles`, `read:services`

## Advanced Usage

### Custom Test Selection

```bash
# Run only ONU-related tests (read and write)
pytest -k "onu"

# Run tests for specific OLT operations
pytest -k "olt"

# Skip slow tests
pytest -m "not slow"
```

### Parallel Execution (if pytest-xdist installed)

```bash
# Run tests in parallel across 4 workers
pytest -n 4
```

**Warning**: Parallel execution may trigger rate limiting on OAuth endpoint. Use `-n auto` for automatic worker count or run serially if rate limit tests fail.

### Integration with CI/CD

```bash
# Exit code 0 = all passed, non-zero = failures
pytest --tb=short --maxfail=5 || exit 1
```

## Support

If tests reveal issues:

1. **Check error messages** - Most failures include helpful descriptions
2. **Review logs** - API logs at `/path/to/logs/` may show detailed errors
3. **Export test report** - Attach JSON report to support tickets
4. **Review documentation** - See `pub/INSTALL.md` and `pub/TROUBLESHOOTING.md`

## Contributing

Found a bug in tests or want to add coverage?

1. Tests should remain **production-safe** (read-only or dry-run only)
2. Follow existing Gherkin scenario patterns
3. Add step definitions to `steps/production_steps.py`
4. Update this README with new test descriptions

## Technical Details

- **Framework**: pytest with pytest-bdd (Gherkin/BDD)
- **Authentication**: OAuth 2.0 Client Credentials flow (RFC 6749)
- **API Pattern**: RESTful v2 endpoints following cnMaestro conventions
- **Safety**: Dry-run mode powered by FastAPI query parameter validation

See architecture documentation in `docs/architecture/production-validation.md` and `docs/architecture/dry-run-mode.md` for design decisions.
