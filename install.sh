#!/bin/bash
# Cambium Fiber API - Linux Installer
# Self-contained installer script for Docker-based deployment
# Usage: bash install.sh [-y|--yes --password=PASSWORD] [--password=PASSWORD]

set -eu

# --- Installer metadata ---
export INSTALLER_VERSION="1.0.0"

# --- Configuration defaults ---
DEFAULT_VERSION="latest"
DEFAULT_PORT="8192"
INSTALL_DIR="/opt/cambium-fiber-api"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
ENV_FILE="${INSTALL_DIR}/.env"
RELEASES_URL="https://github.com/cmbmwifi/cambium-fiber-api/releases/download"

# --- Retry / timeout constants ---
HEALTH_MAX_RETRIES=30
HEALTH_RETRY_DELAY=2
ENDPOINT_MAX_RETRIES=3
CONTAINER_START_DELAY=5
LOG_TAIL_LINES=30

# --- Runtime state (initialised for set -u) ---
YES_TO_ALL=false
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VERSION="${VERSION:-}"
API_PORT="${API_PORT:-}"
DOCS_PASSWORD="${DOCS_PASSWORD:-}"
DOCS_AUTH_ENABLED="${DOCS_AUTH_ENABLED:-}"
DOCS_AUTH_USERNAME=""
DOCS_AUTH_HASH=""
DOCS_USERNAME="${DOCS_USERNAME:-}"
OPEN_BROWSER="${OPEN_BROWSER:-}"
CAMBIUM_API_PORT="${DEFAULT_PORT}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- UI helpers (whiptail → dialog → plain prompt fallback) ---
HAS_WHIPTAIL=false
HAS_DIALOG=false
if command -v whiptail &> /dev/null; then
    HAS_WHIPTAIL=true
elif command -v dialog &> /dev/null; then
    HAS_DIALOG=true
fi

ui_msgbox() {
    local title="$1"
    local message="$2"
    local height="${3:-12}"
    local width="${4:-70}"
    if [ "$HAS_WHIPTAIL" = true ]; then
        whiptail --title "$title" --msgbox "$message" "$height" "$width"
    elif [ "$HAS_DIALOG" = true ]; then
        dialog --title "$title" --msgbox "$message" "$height" "$width"
        clear
    else
        echo ""
        echo "=== $title ==="
        echo -e "$message"
        echo ""
    fi
}

ui_inputbox() {
    local title="$1"
    local prompt="$2"
    local default="$3"
    local height="${4:-10}"
    local width="${5:-70}"
    local result
    if [ "$HAS_WHIPTAIL" = true ]; then
        result=$(whiptail --title "$title" --inputbox "$prompt" "$height" "$width" "$default" 3>&1 1>&2 2>&3) || { echo "$default"; return; }
    elif [ "$HAS_DIALOG" = true ]; then
        result=$(dialog --title "$title" --inputbox "$prompt" "$height" "$width" "$default" 3>&1 1>&2 2>&3) || { echo "$default"; return; }
        clear
    else
        read -rp "$prompt [$default]: " result </dev/tty
        result=${result:-$default}
    fi
    echo "$result"
}

ui_passwordbox() {
    local title="$1"
    local prompt="$2"
    local height="${3:-10}"
    local width="${4:-70}"
    local result
    if [ "$HAS_WHIPTAIL" = true ]; then
        result=$(whiptail --title "$title" --passwordbox "$prompt" "$height" "$width" 3>&1 1>&2 2>&3) || return 1
    elif [ "$HAS_DIALOG" = true ]; then
        result=$(dialog --title "$title" --insecure --passwordbox "$prompt" "$height" "$width" 3>&1 1>&2 2>&3) || return 1
        clear
    else
        read -rsp "$prompt: " result </dev/tty
        echo "" >&2
    fi
    echo "$result"
}

ui_yesno() {
    local title="$1"
    local prompt="$2"
    local default_yes="${3:-true}"
    local height="${4:-10}"
    local width="${5:-70}"
    if [ "$HAS_WHIPTAIL" = true ]; then
        if [ "$default_yes" = true ]; then
            whiptail --title "$title" --yesno "$prompt" "$height" "$width"
        else
            whiptail --title "$title" --defaultno --yesno "$prompt" "$height" "$width"
        fi
        return $?
    elif [ "$HAS_DIALOG" = true ]; then
        if [ "$default_yes" = true ]; then
            dialog --title "$title" --yesno "$prompt" "$height" "$width"
        else
            dialog --title "$title" --defaultno --yesno "$prompt" "$height" "$width"
        fi
        local rc=$?
        clear
        return $rc
    else
        local yn_prompt
        local default_response
        if [ "$default_yes" = true ]; then
            yn_prompt="$prompt [Y/n]: "
            default_response="y"
        else
            yn_prompt="$prompt [y/N]: "
            default_response="n"
        fi
        read -rp "$yn_prompt" response </dev/tty
        response=${response:-$default_response}
        case "$response" in
            [yY][eE][sS]|[yY]) return 0 ;;
            *) return 1 ;;
        esac
    fi
}

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

# --- Cleanup trap for partial installs ---
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo ""
        print_warn "Installation did not complete successfully (exit code: ${exit_code})"
        print_warn "Partial files may remain in ${INSTALL_DIR}"
        if [[ -f "${COMPOSE_FILE}" ]]; then
            if cd "${INSTALL_DIR}" 2>/dev/null; then
                docker compose down 2>/dev/null || true
            fi
        fi
    fi
}
trap cleanup EXIT

install_docker_engine() {
    print_info "Installing Docker Engine via official convenience script (https://get.docker.com)..."
    if ! curl -fsSL https://get.docker.com | sh; then
        print_error "Docker Engine installation failed"
        print_info "Try installing manually: https://docs.docker.com/engine/install/"
        exit 1
    fi
    # Start and enable the Docker service
    if command -v systemctl &> /dev/null; then
        systemctl start docker 2>/dev/null || true
        systemctl enable docker 2>/dev/null || true
    fi
    print_info "Docker Engine installed successfully"
}

check_docker() {
    print_info "Checking Docker installation..."

    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        if [[ "$(uname -s)" == "Linux" ]]; then
            if ui_yesno "Install Docker" "Docker is required but not installed.\n\nInstall Docker Engine automatically?" true; then
                install_docker_engine
            else
                print_info "Install Docker Engine manually: https://docs.docker.com/engine/install/"
                exit 1
            fi
        else
            print_info "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop"
            exit 1
        fi
    fi

    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        if command -v systemctl &> /dev/null; then
            print_info "Try: sudo systemctl start docker"
        else
            print_info "Please start the Docker service and try again"
        fi
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

    cat > "${COMPOSE_FILE}" << 'EOF'
services:
    cambium-fiber-api:
        image: ${CAMBIUM_API_IMAGE:-cambium-fiber-api:latest}
        container_name: cambium-fiber-api
        ports:
            - "${CAMBIUM_API_PORT:-8192}:8192"
        volumes:
            # Configuration file (optional - setup wizard creates if missing)
            - ${CAMBIUM_CONFIG_PATH:-./connections.json}:/app/connections.json${CAMBIUM_CONFIG_MODE:-}
            # Persistent data (discovery database, logs, backups)
            - api-data:/app/data
            - api-logs:/app/logs
            - api-backups:/app/backups
        environment:
            # Version identifier (set by installer, matches the installed image tag)
            - APP_VERSION=${APP_VERSION:-dev}
            # Setup mode - enables /setup wizard when connections.json is missing/invalid
            - ENABLE_SETUP_WIZARD=${ENABLE_SETUP_WIZARD:-true}
            # Optional: Pre-configure OAuth clients (otherwise generated by setup wizard)
            - OAUTH_CLIENT_ID=${OAUTH_CLIENT_ID:-}
            - OAUTH_CLIENT_SECRET=${OAUTH_CLIENT_SECRET:-}
            # Optional: SSL/TLS configuration
            - SSL_CERT_PATH=${SSL_CERT_PATH:-}
            - SSL_KEY_PATH=${SSL_KEY_PATH:-}
        restart: unless-stopped
        healthcheck:
            test: ["CMD", "wget", "--spider", "--quiet", "http://localhost:8192/health"]
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
    TARBALL=$(find "$SCRIPT_DIR" -maxdepth 1 \( -name "cambium-fiber-api-*.tar" -o -name "cambium-fiber-api-*.tar.gz" \) 2>/dev/null | head -n 1)
    if [ -n "${TARBALL}" ]; then
        # Extract version from tarball filename (e.g., cambium-fiber-api-1.0.0-beta.1.tar.gz -> 1.0.0-beta.1)
        DETECTED_VERSION=$(basename "${TARBALL}" | sed -n 's/cambium-fiber-api-\(.*\)\.tar\(\.gz\)\?$/\1/p')
        # 'current' is a dev build placeholder — read the real version from the VERSION file written by make build
        if [ "${DETECTED_VERSION}" = "current" ] && [ -f "${SCRIPT_DIR}/VERSION" ]; then
            DETECTED_VERSION=$(tr -d '[:space:]' < "${SCRIPT_DIR}/VERSION")
        fi
        if [ -n "${DETECTED_VERSION}" ] && [ "${DETECTED_VERSION}" != "dev" ] && [ "${DETECTED_VERSION}" != "current" ]; then
            SUGGESTED_VERSION="${DETECTED_VERSION}"
            print_info "Found local tarball with version: ${DETECTED_VERSION}"
        fi
    fi

    # If suggested version is still 'latest', resolve it from the GitHub API so the prompt is useful
    if [ "${SUGGESTED_VERSION}" = "latest" ]; then
        RESOLVED_LATEST=$(curl -fsSL "https://api.github.com/repos/cmbmwifi/cambium-fiber-api/releases/latest" \
            | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
        if [ -n "${RESOLVED_LATEST}" ]; then
            SUGGESTED_VERSION="${RESOLVED_LATEST}"
        fi
    fi

    # Check for environment variables, prompt if not set (non-interactive mode)
    if [ -n "${VERSION}" ]; then
        print_info "Using version from VERSION: ${VERSION}"
    elif [ "$YES_TO_ALL" = true ]; then
        VERSION="${SUGGESTED_VERSION}"
        print_info "Using version: ${VERSION}"
    else
        VERSION=$(ui_inputbox "Version" "Enter version to install:" "${SUGGESTED_VERSION}")
        VERSION=${VERSION:-$SUGGESTED_VERSION}
        print_info "Using version: ${VERSION}"
    fi

    if [ -n "${API_PORT}" ]; then
        PORT="${API_PORT}"
        print_info "Using port from API_PORT: ${PORT}"
    elif [ "$YES_TO_ALL" = true ]; then
        PORT="${DEFAULT_PORT}"
        print_info "Using port: ${PORT}"
    else
        PORT=$(ui_inputbox "API Port" "Enter port to expose API:" "${DEFAULT_PORT}")
        PORT=${PORT:-$DEFAULT_PORT}
        print_info "Using port: ${PORT}"
    fi

    # Compose project name must be lowercase alphanumeric/hyphens/underscores — strip v prefix and dots
    COMPOSE_PROJECT_NAME="cambium-fiber-api_$(echo "${VERSION}" | sed 's/^v//' | tr '.' '-')"

    cat > "${ENV_FILE}" << EOF
# Cambium Fiber API Configuration
CAMBIUM_API_IMAGE=cambium-fiber-api:${VERSION}
CAMBIUM_API_PORT=${PORT}
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}
APP_VERSION=${VERSION}
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

    if [ -n "${DOCS_AUTH_ENABLED}" ]; then
        if [ "${DOCS_AUTH_ENABLED}" = "false" ]; then
            print_warn "DOCS_AUTH_ENABLED=false detected - documentation will be publicly accessible"
            PROTECT_DOCS="N"
        else
            PROTECT_DOCS="Y"
            print_info "Using DOCS_AUTH_ENABLED from environment: ${PROTECT_DOCS}"
        fi
    elif [ "$YES_TO_ALL" = true ]; then
        PROTECT_DOCS="Y"
    else
        if ui_yesno "Documentation Auth" "The /docs and /setup endpoints can be protected\nwith HTTP Basic Authentication.\n\nEnable authentication? (Recommended)" true; then
            PROTECT_DOCS="Y"
        else
            PROTECT_DOCS="N"
        fi
    fi

    if [[ "${PROTECT_DOCS}" =~ ^[Yy]$ ]]; then
        if [ -n "${DOCS_USERNAME}" ]; then
            DOCS_USER="${DOCS_USERNAME}"
            print_info "Using DOCS_USERNAME from environment: ${DOCS_USER}"
        elif [ "$YES_TO_ALL" = true ]; then
            DOCS_USER="admin"
            print_info "Using username: ${DOCS_USER}"
        else
            DOCS_USER=$(ui_inputbox "Auth Username" "Enter username for /docs and /setup:" "admin")
            DOCS_USER=${DOCS_USER:-admin}
        fi

        if [ -n "${DOCS_PASSWORD}" ]; then
            DOCS_PASS="${DOCS_PASSWORD}"
            print_info "Using DOCS_PASSWORD from environment"
        else
            while true; do
                DOCS_PASS=$(ui_passwordbox "Auth Password" "Enter password for documentation auth:")
                if [ -z "${DOCS_PASS}" ]; then
                    ui_msgbox "Error" "Password cannot be empty!" 8 50
                    continue
                fi
                DOCS_PASS_CONFIRM=$(ui_passwordbox "Confirm Password" "Confirm password:")
                if [ "${DOCS_PASS}" != "${DOCS_PASS_CONFIRM}" ]; then
                    ui_msgbox "Error" "Passwords do not match! Please try again." 8 50
                    continue
                fi
                break
            done
        fi

        print_info "Generating password hash..."

        DOCS_HASH=$(DOCS_PASS="${DOCS_PASS}" docker run --rm -e DOCS_PASS python:3.11-slim \
            bash -c 'pip install -q bcrypt >/dev/null 2>&1 && python3 -c "import os, bcrypt
pwd = os.environ[\"DOCS_PASS\"].encode(\"utf-8\")
print(bcrypt.hashpw(pwd, bcrypt.gensalt()).decode(\"utf-8\"))
"' 2>/dev/null)

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

create_connections_example_file() {
    # If the example file already exists in INSTALL_DIR (e.g. from a prior step), keep it.
    [ -f "${INSTALL_DIR}/connections.json.example" ] && return 0

    # Prefer a local copy alongside the script (tarball install).
    if [ -f "$SCRIPT_DIR/connections.json.example" ]; then
        cp "$SCRIPT_DIR/connections.json.example" "${INSTALL_DIR}/connections.json.example"
        return 0
    fi

    # When run via 'curl | bash' there is no local file — write the default inline.
    print_info "Writing default connections.json.example..."
    cat > "${INSTALL_DIR}/connections.json.example" << 'EOF'
{
  "docs_auth": {
    "username": "admin",
    "password_hash": "$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyWpRE8z.jSS"
  },
  "health": {
    "connection_timeout": 2,
    "retry_interval": 30,
    "success_threshold": 10
  },
  "groups": [],
  "virtual_stacks": [],
  "olts": [],
  "cache_ttl": {
    "bulk_ttl": 3600,
    "single_ttl": 30
  },
  "jwt_secret": "REPLACE_WITH_RANDOM_SECRET_IN_PRODUCTION",
  "oauth": {
    "clients": [
      {
        "client_id": "example-admin",
        "client_secret": "password",
        "client_secret_hash": "5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8",
        "scopes": ["admin"],
        "enabled": true,
        "description": "Example admin client for validation tests (default secret: 'password' - change in production)"
      }
    ]
  }
}
EOF
}

create_connections_file() {
    print_info "Creating connections configuration file..."

    CONNECTIONS_FILE="${INSTALL_DIR}/connections.json"

    if [ -d "${CONNECTIONS_FILE}" ]; then
        print_warn "Removing stale connections.json directory from previous install"
        rm -rf "${CONNECTIONS_FILE}"
    fi

    # Copy template from installation package to INSTALL_DIR
    if [ -f "$SCRIPT_DIR/connections.json.example" ]; then
        cp "$SCRIPT_DIR/connections.json.example" "${INSTALL_DIR}/connections.json.example"
    elif [ ! -f "${INSTALL_DIR}/connections.json.example" ]; then
        print_error "connections.json.example not found in $SCRIPT_DIR or ${INSTALL_DIR}"
        exit 1
    fi

    cp "${INSTALL_DIR}/connections.json.example" "${CONNECTIONS_FILE}"

    if [[ "${DOCS_AUTH_ENABLED}" = "true" ]]; then
        CFG_FILE="${CONNECTIONS_FILE}" \
        AUTH_USER="${DOCS_AUTH_USERNAME}" \
        AUTH_HASH="${DOCS_AUTH_HASH}" \
        python3 -c "
import json, os

filepath = os.environ['CFG_FILE']
with open(filepath, 'r') as f:
    config = json.load(f)

config['docs_auth'] = {
    'username': os.environ['AUTH_USER'],
    'password_hash': os.environ['AUTH_HASH']
}

with open(filepath, 'w') as f:
    json.dump(config, f, indent=2)
"
        print_info "connections.json created with documentation authentication"
    else
        CFG_FILE="${CONNECTIONS_FILE}" \
        python3 -c "
import json, os

filepath = os.environ['CFG_FILE']
with open(filepath, 'r') as f:
    config = json.load(f)

config.pop('docs_auth', None)

with open(filepath, 'w') as f:
    json.dump(config, f, indent=2)
"
        print_info "connections.json created (no authentication, will be configured via setup wizard)"
    fi
}

load_or_pull_image() {
    print_info "Checking for Docker image..."

    # Source env file to get desired IMAGE variable
    # shellcheck source=/dev/null
    source "${ENV_FILE}"

    # Check if tarball exists in script directory
    TARBALL=$(find "$SCRIPT_DIR" -maxdepth 1 \( -name "cambium-fiber-api-*.tar" -o -name "cambium-fiber-api-*.tar.gz" \) 2>/dev/null | head -n 1)

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
        # Derive tarball name and try to download from the distribution repo.
        # VERSION may include a 'v' prefix already; normalise to vX.Y.Z lowercase
        # (GitHub Release tags are always lowercased by make release).
        IMAGE_VERSION="${CAMBIUM_API_IMAGE#*:}"
        IMAGE_VERSION_LOWER=$(printf '%s' "${IMAGE_VERSION}" | tr '[:upper:]' '[:lower:]')

        # Resolve 'latest' to the actual latest release tag via GitHub API
        if [ "${IMAGE_VERSION_LOWER}" = "latest" ]; then
            print_info "Resolving latest release version from GitHub..."
            RESOLVED=$(curl -fsSL "https://api.github.com/repos/cmbmwifi/cambium-fiber-api/releases/latest" \
                | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
            if [ -z "${RESOLVED}" ]; then
                print_error "Could not resolve latest release from GitHub API."
                print_info "Specify a version explicitly, e.g.: VERSION=v1.0.0-rc3 bash install.sh"
                exit 1
            fi
            IMAGE_VERSION_LOWER="${RESOLVED}"
            print_info "Latest release: ${IMAGE_VERSION_LOWER}"
        fi

        case "${IMAGE_VERSION_LOWER}" in
            v*) TARBALL_VERSION="${IMAGE_VERSION_LOWER}" ;;
            *)  TARBALL_VERSION="v${IMAGE_VERSION_LOWER}" ;;
        esac
        TARBALL_FILENAME="cambium-fiber-api-${TARBALL_VERSION}.tar.gz"
        TARBALL_URL="${RELEASES_URL}/${TARBALL_VERSION}/${TARBALL_FILENAME}"
        TARBALL_DEST="${INSTALL_DIR}/${TARBALL_FILENAME}"

        print_info "Downloading Docker image from GitHub..."
        print_info "  ${TARBALL_URL}"

        if curl -fsSL --progress-bar "${TARBALL_URL}" -o "${TARBALL_DEST}"; then
            print_info "Download complete"
            print_info "Loading Docker image from tarball..."
            docker load -i "${TARBALL_DEST}"
            docker tag "cambium-fiber-api:current" "${CAMBIUM_API_IMAGE}" 2>/dev/null || true
            print_info "Image loaded successfully"
            rm -f "${TARBALL_DEST}"  # save disk space after load
        else
            print_error "Failed to download image from ${TARBALL_URL}"
            print_info "Check the version (entered: ${IMAGE_VERSION}) matches a published release."
            print_info "Browse available files: https://github.com/cmbmwifi/cambium-fiber-api"
            exit 1
        fi
    fi
}

validate_endpoint() {
    local url="$1"
    # shellcheck disable=SC2034
    local name="$2"  # descriptive parameter for logging context
    local max_retries="${3:-3}"
    local acceptable_codes="${4:-200}"
    local retry_count=0

    while [ "$retry_count" -lt "$max_retries" ]; do
        response=$(curl -s -w "\n%{http_code}" "$url" 2>&1)
        http_code=$(echo "$response" | tail -n 1)

        for code in $(echo "$acceptable_codes" | tr ',' ' '); do
            if [ "$http_code" -eq "$code" ]; then
                return 0
            fi
        done

        retry_count=$((retry_count + 1))
        [ "$retry_count" -lt "$max_retries" ] && sleep 1
    done
    return 1
}

check_container_logs() {
    print_info "Checking container logs for errors..."
    echo ""
    echo "==================== Last ${LOG_TAIL_LINES} Log Lines ===================="
    docker logs --tail "${LOG_TAIL_LINES}" cambium-fiber-api 2>&1
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
            # shellcheck source=/dev/null
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
            cd "${INSTALL_DIR}" || exit 1
            docker compose down 2>/dev/null || true
            docker rm cambium-fiber-api 2>/dev/null || true
        fi
    fi
}

start_container() {
    print_info "Starting Cambium Fiber API..."

    cd "${INSTALL_DIR}" || exit 1
    docker compose --env-file "${ENV_FILE}" up -d

    # shellcheck source=/dev/null
    source "${ENV_FILE}"

    print_info "Waiting for container to start..."
    sleep "${CONTAINER_START_DELAY}"

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
    RETRY_COUNT=0

    while [[ $RETRY_COUNT -lt $HEALTH_MAX_RETRIES ]]; do
        if validate_endpoint "http://localhost:${CAMBIUM_API_PORT}/health" "health" 1; then
            HEALTH_OK=true
            break
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo -n "."
        sleep "${HEALTH_RETRY_DELAY}"
    done
    echo ""

    if [ "$HEALTH_OK" = false ]; then
        print_error "✗ Health endpoint failed to respond"
        check_container_logs
        print_troubleshooting
        exit 1
    fi

    # Now validate the other critical endpoints
    # Session-based auth returns 307 redirects when login is required
    EXPECTED_DOCS_CODES="200"
    if [ "${DOCS_AUTH_ENABLED}" = "true" ]; then
        EXPECTED_DOCS_CODES="200,303,307,401"
    fi

    if validate_endpoint "http://localhost:${CAMBIUM_API_PORT}/docs" "docs" "${ENDPOINT_MAX_RETRIES}" "${EXPECTED_DOCS_CODES}"; then
        DOCS_OK=true
    else
        print_error "✗ /docs endpoint is not responding or returning errors"
        DOCS_OK=false
    fi

    if validate_endpoint "http://localhost:${CAMBIUM_API_PORT}/setup" "setup" "${ENDPOINT_MAX_RETRIES}" "${EXPECTED_DOCS_CODES}"; then
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

    # shellcheck source=/dev/null
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
    # shellcheck source=/dev/null
    source "${ENV_FILE}"

    # ANSI escape codes for hyperlinks (OSC 8)
    BLUE='\033[1;34m'
    CYAN='\033[1;36m'
    BOLD='\033[1m'
    NC='\033[0m'

    # Hyperlink function: creates clickable link if terminal supports it
    hyperlink() {
        local url="$1"
        local text="${2:-$url}"
        echo -e "\e]8;;${url}\e\\${BLUE}${text}${NC}\e]8;;\e\\"
    }

    echo ""
    echo "================================================================"
    echo -e "  ${GREEN}✓ Installation Complete!${NC}"
    echo "================================================================"
    echo ""
    echo -e "  ${BOLD}${YELLOW}Next Step:${NC} Open $(hyperlink "http://localhost:${CAMBIUM_API_PORT}/setup") to configure your OLTs"
    echo ""
    echo -e "  ${CYAN}API Documentation:${NC} $(hyperlink "http://localhost:${CAMBIUM_API_PORT}/docs")"
    echo -e "  ${CYAN}View Logs:${NC} docker logs -f cambium-fiber-api"
    echo ""
    echo "================================================================"
    echo ""
}

# Main installation flow
main() {
    # When piped (e.g. curl | bash), bash's stdin is the pipe (EOF after download).
    # Each read below uses </dev/tty explicitly so the global stdin is never changed
    # (a global exec </dev/tty would leave bash appearing interactive after the script
    # finishes, requiring Ctrl+C to get the prompt back).

    echo ""
    print_info "Cambium Fiber API - Linux Installer"
    print_info "===================================="
    echo ""

    if [ "$HAS_WHIPTAIL" = true ] || [ "$HAS_DIALOG" = true ]; then
        ui_msgbox "Cambium Fiber API" "Unified Stateless REST API for managing fiber networks across multiple OLTs. Pre-configure ONUs before deployment, track devices network-wide, and integrate with OSS/BSS platforms through a single endpoint.\n\nFor: ISPs, MSPs, and system integrators managing Cambium Fiber networks" 14 74
    fi

    check_docker
    check_docker_compose
    create_install_dir
    download_compose_file
    create_env_file
    prompt_docs_auth

    create_connections_example_file

    create_connections_file
    check_existing_installation
    load_or_pull_image
    start_container
    open_browser
    print_success
}

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        -y|--yes)
            YES_TO_ALL=true
            ;;
        --password=*)
            DOCS_PASSWORD="${arg#*=}"
            ;;
    esac
done

if [ "$YES_TO_ALL" = true ] && [ -z "${DOCS_PASSWORD}" ] && [ "${DOCS_AUTH_ENABLED}" != "false" ]; then
    print_error "--password=PASSWORD is required when using -y/--yes"
    echo "Usage: bash install.sh -y --password=PASSWORD"
    exit 1
fi

# Run main installation
main "$@"
