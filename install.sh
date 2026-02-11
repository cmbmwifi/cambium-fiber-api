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

create_connections_file() {
    print_info "Creating connections configuration file..."

    CONNECTIONS_FILE="${INSTALL_DIR}/connections.json"

    # Remove if it exists as a directory (from previous failed install)
    if [ -d "${CONNECTIONS_FILE}" ]; then
        print_warn "Removing stale connections.json directory from previous install"
        rm -rf "${CONNECTIONS_FILE}"
    fi

    # Create empty connections.json (setup wizard will configure it)
    cat > "${CONNECTIONS_FILE}" << 'EOF'
{}
EOF

    print_info "Empty connections.json created (will be configured via setup wizard)"
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

start_container() {
    print_info "Starting Cambium Fiber API..."

    cd "${INSTALL_DIR}"
    docker compose --env-file "${ENV_FILE}" up -d

    print_info "Waiting for API to be ready..."

    # Wait for health check
    MAX_RETRIES=30
    RETRY_COUNT=0

    source "${ENV_FILE}"
    HEALTH_URL="http://localhost:${CAMBIUM_API_PORT}/health"

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if curl -sf "${HEALTH_URL}" > /dev/null 2>&1; then
            print_info "API is ready!"
            return 0
        fi

        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo -n "."
        sleep 2
    done

    echo ""
    print_warn "API did not become ready within expected time"
    print_info "Check logs with: docker logs cambium-fiber-api"
}

open_browser() {
    # Check if browser should be opened (skip for headless/CI environments)
    # If OPEN_BROWSER is set (uncommented), skip browser open
    if [ -n "${OPEN_BROWSER}" ]; then
        print_info "Skipping browser open (headless mode: OPEN_BROWSER is set)"
        source "${ENV_FILE}"
        print_info "Setup wizard URL: http://localhost:${CAMBIUM_API_PORT}/setup"
        return
    fi

    source "${ENV_FILE}"
    SETUP_URL="http://localhost:${CAMBIUM_API_PORT}/setup"

    print_info "Opening setup wizard in browser..."

    # Try different browser commands
    if command -v xdg-open &> /dev/null; then
        xdg-open "${SETUP_URL}" &> /dev/null &
    elif command -v gnome-open &> /dev/null; then
        gnome-open "${SETUP_URL}" &> /dev/null &
    elif command -v open &> /dev/null; then
        open "${SETUP_URL}" &> /dev/null &
    else
        print_warn "Could not auto-open browser"
        print_info "Please open this URL manually: ${SETUP_URL}"
        return
    fi

    print_info "Setup wizard opened at: ${SETUP_URL}"
}

print_success() {
    echo ""
    print_info "================================================================"
    print_info "  Cambium Fiber API Installation Complete!"
    print_info "================================================================"
    echo ""

    source "${ENV_FILE}"

    print_info "Installation directory: ${INSTALL_DIR}"
    print_info "API URL: http://localhost:${CAMBIUM_API_PORT}"
    print_info "Setup wizard: http://localhost:${CAMBIUM_API_PORT}/setup"
    print_info "API docs: http://localhost:${CAMBIUM_API_PORT}/docs"
    echo ""
    print_info "Common commands:"
    print_info "  Start:   cd ${INSTALL_DIR} && docker compose up -d"
    print_info "  Stop:    cd ${INSTALL_DIR} && docker compose down"
    print_info "  Logs:    docker logs -f cambium-fiber-api"
    print_info "  Status:  docker ps | grep cambium-fiber-api"
    echo ""
    print_info "Complete the setup wizard to configure your OLT connections"
    print_info "================================================================"
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
    create_connections_file
    load_or_pull_image
    start_container
    open_browser
    print_success
}

# Run main installation
main
