#!/bin/bash
# Cambium Fiber API - Linux Installer
# Self-contained installer script for Docker-based deployment
# Usage: curl -fsSL https://raw.githubusercontent.com/USERNAME/REPO/main/install.sh | bash

set -e  # Exit on error

# Load .env if it exists (for non-interactive installs)
if [ -f ".env" ]; then
    set -a  # Export all variables
    source .env
    set +a
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
DEFAULT_VERSION="latest"
DEFAULT_PORT="8000"
INSTALL_DIR="/opt/cambium-fiber-api"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
ENV_FILE="${INSTALL_DIR}/.env"

# Functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_docker() {
    print_info "Checking Docker installation..."

    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        print_info "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        print_info "Please start Docker Desktop and try again"
        exit 1
    fi

    print_info "Docker is ready ($(docker --version))"
}

check_docker_compose() {
    print_info "Checking Docker Compose..."

    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not available"
        print_info "Please install Docker Compose v2 or Docker Desktop"
        exit 1
    fi

    print_info "Docker Compose is ready ($(docker compose version))"
}

create_install_dir() {
    print_info "Creating installation directory: ${INSTALL_DIR}"

    # Check if we need sudo for /opt
    if [[ ! -w "$(dirname "${INSTALL_DIR}")" ]]; then
        print_info "Creating directory requires sudo privileges..."
        sudo mkdir -p "${INSTALL_DIR}"
        sudo chown "${USER}:${USER}" "${INSTALL_DIR}"
    else
        mkdir -p "${INSTALL_DIR}"
    fi
}

download_compose_file() {
    print_info "Downloading docker-compose.yml..."

    # TODO: Replace with actual repository URL
    COMPOSE_URL="https://raw.githubusercontent.com/USERNAME/REPO/main/docker-compose.yml"

    cat > "${COMPOSE_FILE}" << 'EOF'
version: '3.8'

services:
  cambium-fiber-api:
    image: ${CAMBIUM_API_IMAGE:-cambium-fiber-api:latest}
    container_name: cambium-fiber-api
    ports:
      - "${CAMBIUM_API_PORT:-8000}:8000"
    volumes:
      - ${CAMBIUM_CONFIG_PATH:-./connections.json}:/app/connections.json${CAMBIUM_CONFIG_MODE:-}
      - api-data:/app/data
      - api-logs:/app/logs
      - api-backups:/app/backups
    environment:
      - ENABLE_SETUP_WIZARD=${ENABLE_SETUP_WIZARD:-true}
      - OAUTH_CLIENT_ID=${OAUTH_CLIENT_ID:-}
      - OAUTH_CLIENT_SECRET=${OAUTH_CLIENT_SECRET:-}
      - SSL_CERT_PATH=${SSL_CERT_PATH:-}
      - SSL_KEY_PATH=${SSL_KEY_PATH:-}
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--spider", "--quiet", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

volumes:
  api-data:
    driver: local
  api-logs:
    driver: local
  api-backups:
    driver: local
EOF

    print_info "docker-compose.yml created"
}

create_env_file() {
    print_info "Creating environment configuration..."

    # Check for local tarball to suggest version
    SUGGESTED_VERSION="${DEFAULT_VERSION}"
    TARBALL=$(find . -maxdepth 1 -name "cambium-fiber-api-*.tar" -o -name "cambium-fiber-api-*.tar.gz" 2>/dev/null | head -n 1)
    if [ -n "${TARBALL}" ]; then
        # Extract version from tarball filename (e.g., cambium-fiber-api-1.0.0-beta.1.tar.gz -> 1.0.0-beta.1)
        DETECTED_VERSION=$(basename "${TARBALL}" | sed -n 's/cambium-fiber-api-\(.*\)\.tar\(\.gz\)\?$/\1/p')
        if [ -n "${DETECTED_VERSION}" ]; then
            SUGGESTED_VERSION="${DETECTED_VERSION}"
            print_info "Found local tarball with version: ${DETECTED_VERSION}"
        fi
    fi

    # Check for environment variables, prompt if not set (non-interactive mode)
    if [ -n "${VERSION}" ]; then
        print_info "Using version from VERSION: ${VERSION}"
    else
        read -p "Enter version to install [${SUGGESTED_VERSION}]: " VERSION
        VERSION=${VERSION:-$SUGGESTED_VERSION}
    fi

    if [ -n "${API_PORT}" ]; then
        PORT="${API_PORT}"
        print_info "Using port from API_PORT: ${PORT}"
    else
        read -p "Enter port to expose API [${DEFAULT_PORT}]: " PORT
        PORT=${PORT:-$DEFAULT_PORT}
    fi

    cat > "${ENV_FILE}" << EOF
# Cambium Fiber API Configuration
CAMBIUM_API_IMAGE=cambium-fiber-api:${VERSION}
CAMBIUM_API_PORT=${PORT}
ENABLE_SETUP_WIZARD=\${ENABLE_SETUP_WIZARD:-true}
OAUTH_CLIENT_ID=\${OAUTH_CLIENT_ID:-}
OAUTH_CLIENT_SECRET=\${OAUTH_CLIENT_SECRET:-}
SSL_CERT_PATH=\${SSL_CERT_PATH:-}
SSL_KEY_PATH=\${SSL_KEY_PATH:-}
EOF

    print_info "Environment file created: ${ENV_FILE}"
}

prompt_docs_auth() {
    print_info "Documentation Authentication Setup"
    echo ""
    print_warn "SECURITY: The /docs and /setup endpoints WILL be protected with HTTP Basic Authentication."
    echo ""

    if [ -n "${DOCS_AUTH_ENABLED}" ]; then
        if [ "${DOCS_AUTH_ENABLED}" = "false" ]; then
            print_warn "DOCS_AUTH_ENABLED=false detected - documentation will be publicly accessible"
            PROTECT_DOCS="N"
        else
            PROTECT_DOCS="Y"
            print_info "Using DOCS_AUTH_ENABLED from environment: ${PROTECT_DOCS}"
        fi
    else
        echo "Press ENTER to protect endpoints (recommended)"
        read -p "Or type exactly 'I understand the risk' to disable protection: " DISABLE_PROTECTION
        if [ "${DISABLE_PROTECTION}" = "I understand the risk" ]; then
            PROTECT_DOCS="N"
        else
            PROTECT_DOCS="Y"
        fi
    fi

    if [[ "${PROTECT_DOCS}" =~ ^[Yy]$ ]]; then
        if [ -n "${DOCS_USERNAME}" ]; then
            DOCS_USER="${DOCS_USERNAME}"
            print_info "Using DOCS_USERNAME from environment: ${DOCS_USER}"
        else
            read -p "Enter username for /docs and /setup [admin]: " DOCS_USER
            DOCS_USER=${DOCS_USER:-admin}
        fi

        if [ -n "${DOCS_PASSWORD}" ]; then
            DOCS_PASS="${DOCS_PASSWORD}"
            print_info "Using DOCS_PASSWORD from environment"
        else
            read -sp "Enter password: " DOCS_PASS
            echo ""
            read -sp "Confirm password: " DOCS_PASS_CONFIRM
            echo ""

            if [ "${DOCS_PASS}" != "${DOCS_PASS_CONFIRM}" ]; then
                print_error "Passwords do not match!"
                exit 1
            fi

            if [ -z "${DOCS_PASS}" ]; then
                print_error "Password cannot be empty!"
                exit 1
            fi
        fi

        print_info "Generating password hash..."

        DOCS_HASH=$(docker run --rm python:3.11-slim bash -c "pip install -q bcrypt && python -c \"import bcrypt; print(bcrypt.hashpw('${DOCS_PASS}'.encode('utf-8'), bcrypt.gensalt()).decode('utf-8'))\"" 2>/dev/null)

        if [ -z "${DOCS_HASH}" ]; then
            print_error "Failed to generate password hash"
            exit 1
        fi

        export DOCS_AUTH_ENABLED="true"
        export DOCS_AUTH_USERNAME="${DOCS_USER}"
        export DOCS_AUTH_HASH="${DOCS_HASH}"

        print_info "✓ Documentation authentication configured"
    else
        export DOCS_AUTH_ENABLED="false"
        print_warn "Documentation endpoints will be publicly accessible"
    fi
    echo ""
}

create_connections_file() {
    print_info "Creating connections configuration file..."

    CONNECTIONS_FILE="${INSTALL_DIR}/connections.json"

    # Remove if it exists as a directory (from previous failed install)
    if [ -d "${CONNECTIONS_FILE}" ]; then
        print_warn "Removing stale connections.json directory from previous install"
        rm -rf "${CONNECTIONS_FILE}"
    fi

    if [ "${DOCS_AUTH_ENABLED}" = "true" ]; then
        cat > "${CONNECTIONS_FILE}" << EOF
{
  "docs_auth": {
    "username": "${DOCS_AUTH_USERNAME}",
    "password_hash": "${DOCS_AUTH_HASH}"
  }
}
EOF
        print_info "connections.json created with documentation authentication"
    else
        cat > "${CONNECTIONS_FILE}" << 'EOF'
{}
EOF
        print_info "Empty connections.json created (will be configured via setup wizard)"
    fi
}

load_or_pull_image() {
    print_info "Checking for Docker image..."

    # Source env file to get desired IMAGE variable
    source "${ENV_FILE}"

    # Check if tarball exists in current directory
    TARBALL=$(find . -maxdepth 1 -name "cambium-fiber-api-*.tar" -o -name "cambium-fiber-api-*.tar.gz" 2>/dev/null | head -n 1)

    if [ -n "${TARBALL}" ]; then
        print_info "Found local tarball: ${TARBALL}"
        print_info "Loading Docker image from tarball..."

        # Extract version from tarball filename
        TARBALL_VERSION=$(basename "${TARBALL}" | sed -n 's/cambium-fiber-api-\(.*\)\.tar\(\.gz\)\?$/\1/p')

        # Load the image from tarball
        if [[ "${TARBALL}" == *.tar.gz ]]; then
            gunzip -c "${TARBALL}" | docker load
        else
            docker load -i "${TARBALL}"
        fi

        print_info "Image loaded successfully"

        # Re-tag the loaded image to match the requested version if different
        if [ -n "${TARBALL_VERSION}" ] && [ "${CAMBIUM_API_IMAGE}" != "cambium-fiber-api:${TARBALL_VERSION}" ]; then
            print_info "Tagging image as: ${CAMBIUM_API_IMAGE}"
            docker tag "cambium-fiber-api:${TARBALL_VERSION}" "${CAMBIUM_API_IMAGE}"
        fi
    else
        print_warn "No local tarball found - pulling from registry"
        print_info "Pulling Docker image..."

        if docker pull "${CAMBIUM_API_IMAGE}"; then
            print_info "Image pulled successfully"
        else
            print_error "Failed to pull image from registry"
            print_info "Please download the tarball manually or check registry access"
            exit 1
        fi
    fi
}

validate_endpoint() {
    local url="$1"
    local name="$2"
    local max_retries="${3:-3}"
    local acceptable_codes="${4:-200}"
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        response=$(curl -s -w "\n%{http_code}" "$url" 2>&1)
        http_code=$(echo "$response" | tail -n 1)

        for code in $(echo "$acceptable_codes" | tr ',' ' '); do
            if [ "$http_code" -eq "$code" ]; then
                return 0
            fi
        done

        retry_count=$((retry_count + 1))
        [ $retry_count -lt $max_retries ] && sleep 1
    done
    return 1
}

check_container_logs() {
    print_info "Checking container logs for errors..."
    echo ""
    echo "==================== Last 30 Log Lines ===================="
    docker logs --tail 30 cambium-fiber-api 2>&1
    echo "==========================================================="
    echo ""
}

print_troubleshooting() {
    echo ""
    print_error "================================================================"
    print_error "  Installation Incomplete - Endpoints Not Ready"
    print_error "================================================================"
    echo ""
    print_info "Troubleshooting Steps:"
    echo ""
    print_info "1. Check container status:"
    print_info "   docker ps -a | grep cambium-fiber-api"
    echo ""
    print_info "2. View full logs:"
    print_info "   docker logs cambium-fiber-api"
    echo ""
    print_info "3. Check for common issues:"
    print_info "   - Port ${CAMBIUM_API_PORT} already in use: lsof -i:${CAMBIUM_API_PORT}"
    print_info "   - Permissions on connections.json: ls -la ${INSTALL_DIR}/connections.json"
    print_info "   - Docker resources: docker system df"
    echo ""
    print_info "4. Try restarting the container:"
    print_info "   cd ${INSTALL_DIR} && docker compose down"
    print_info "   docker compose up -d"
    echo ""
    print_info "5. Check Docker networking:"
    print_info "   curl -v http://localhost:${CAMBIUM_API_PORT}/health"
    echo ""
    print_info "Common Issues:"
    print_info "  - If /health works but /docs fails: Check for Python import errors in logs"
    print_info "  - If connection refused: Container may not be running or port not exposed"
    print_info "  - If 500 errors: Check application logs for exceptions"
    echo ""
    print_info "================================================================"
}

check_existing_installation() {
    # Check if container already exists
    if docker ps -a --format '{{.Names}}' | grep -q '^cambium-fiber-api$'; then
        if docker ps --format '{{.Names}}' | grep -q '^cambium-fiber-api$'; then
            # Container is running
            source "${ENV_FILE}"
            print_warn "Cambium Fiber API is already installed and running"
            echo ""
            print_info "The service is accessible at:"
            print_info "  API Docs: http://localhost:${CAMBIUM_API_PORT}/docs"
            print_info "  Health: http://localhost:${CAMBIUM_API_PORT}/health"
            echo ""
            print_info "To reinstall, first uninstall with: ./uninstall.sh"
            echo ""
            exit 0
        else
            # Container exists but is stopped - clean it up
            print_info "Found stopped container, removing it..."
            cd "${INSTALL_DIR}"
            docker compose down 2>/dev/null || true
            docker rm cambium-fiber-api 2>/dev/null || true
        fi
    fi
}

start_container() {
    print_info "Starting Cambium Fiber API..."

    cd "${INSTALL_DIR}"
    docker compose --env-file "${ENV_FILE}" up -d

    source "${ENV_FILE}"

    print_info "Waiting for container to start..."
    sleep 5

    # Check if container is actually running
    if ! docker ps | grep -q cambium-fiber-api; then
        print_error "Container failed to start!"
        check_container_logs
        print_troubleshooting
        exit 1
    fi

    print_info "Validating endpoints..."

    # Track which endpoints work
    HEALTH_OK=false
    DOCS_OK=false
    SETUP_OK=false

    # Wait for health endpoint with retry
    MAX_RETRIES=30
    RETRY_COUNT=0

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if validate_endpoint "http://localhost:${CAMBIUM_API_PORT}/health" "health" 1; then
            HEALTH_OK=true
            break
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo -n "."
        sleep 2
    done
    echo ""

    if [ "$HEALTH_OK" = false ]; then
        print_error "✗ Health endpoint failed to respond"
        check_container_logs
        print_troubleshooting
        exit 1
    fi

    # Now validate the other critical endpoints
    # If docs auth is enabled, 401 Unauthorized is expected and means endpoints are working
    EXPECTED_DOCS_CODES="200"
    if [ "${DOCS_AUTH_ENABLED}" = "true" ]; then
        EXPECTED_DOCS_CODES="200,401"
    fi

    if validate_endpoint "http://localhost:${CAMBIUM_API_PORT}/docs" "docs" 3 "${EXPECTED_DOCS_CODES}"; then
        DOCS_OK=true
    else
        print_error "✗ /docs endpoint is not responding or returning errors"
        DOCS_OK=false
    fi

    if validate_endpoint "http://localhost:${CAMBIUM_API_PORT}/setup" "setup" 3 "${EXPECTED_DOCS_CODES}"; then
        SETUP_OK=true
    else
        print_error "✗ /setup endpoint is not responding or returning errors"
        SETUP_OK=false
    fi

    # If any critical endpoint failed, show diagnostics and fail
    if [ "$DOCS_OK" = false ] || [ "$SETUP_OK" = false ]; then
        echo ""
        print_error "Critical endpoints are not responding correctly!"
        print_info "Getting diagnostic information..."
        check_container_logs

        # Test each endpoint manually to get detailed error info
        echo ""
        print_info "Detailed endpoint testing:"
        for endpoint in "health" "docs" "setup"; do
            echo ""
            print_info "Testing /$endpoint:"
            curl -v "http://localhost:${CAMBIUM_API_PORT}/$endpoint" 2>&1 | head -n 20
        done

        print_troubleshooting
        exit 1
    fi

    print_info "✓ Ready"

    # Export status for print_success
    export HEALTH_OK DOCS_OK SETUP_OK
}

open_browser() {
    # Check if browser should be opened (skip for headless/CI environments)
    # If OPEN_BROWSER is set (uncommented), skip browser open
    if [ -n "${OPEN_BROWSER}" ]; then
        return
    fi

    source "${ENV_FILE}"
    SETUP_URL="http://localhost:${CAMBIUM_API_PORT}/setup"

    # Try different browser commands
    if command -v xdg-open &> /dev/null; then
        xdg-open "${SETUP_URL}" &> /dev/null &
    elif command -v gnome-open &> /dev/null; then
        gnome-open "${SETUP_URL}" &> /dev/null &
    elif command -v open &> /dev/null; then
        open "${SETUP_URL}" &> /dev/null &
    fi
}

print_success() {
    source "${ENV_FILE}"

    echo ""
    echo "================================================================"
    echo "  ✓ Installation Complete!"
    echo "================================================================"
    echo ""
    echo "  Next: Open http://localhost:${CAMBIUM_API_PORT}/setup to configure your OLTs"
    echo ""
    echo "  API Documentation: http://localhost:${CAMBIUM_API_PORT}/docs"
    echo "  View Logs: docker logs -f cambium-fiber-api"
    echo ""
    echo "================================================================"
    echo ""
}

# Main installation flow
main() {
    echo ""
    print_info "Cambium Fiber API - Linux Installer"
    print_info "===================================="
    echo ""

    check_docker
    check_docker_compose
    create_install_dir
    download_compose_file
    create_env_file
    prompt_docs_auth
    create_connections_file
    check_existing_installation
    load_or_pull_image
    start_container
    open_browser
    print_success
}

# Run main installation
main
