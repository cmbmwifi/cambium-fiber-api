#!/bin/bash
# Cambium Fiber API - Linux Uninstaller
# Removes installed Cambium Fiber API components
# Usage: bash uninstall.sh [-y|--yes]

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/cambium-fiber-api"
CONTAINER_NAME="cambium-fiber-api"
IMAGE_NAME="cambium-fiber-api"
YES_TO_ALL=false

# --- UI helpers (whiptail → dialog → plain prompt fallback) ---
HAS_WHIPTAIL=false
HAS_DIALOG=false
if command -v whiptail &> /dev/null; then
    HAS_WHIPTAIL=true
elif command -v dialog &> /dev/null; then
    HAS_DIALOG=true
fi

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

confirm() {
    local prompt="$1"
    local default="${2:-n}"

    if [ "$YES_TO_ALL" = true ]; then
        echo -e "${prompt} [auto-yes]"
        return 0
    fi

    local default_yes=false
    if [ "$default" = "y" ]; then
        default_yes=true
    fi

    if [ "$HAS_WHIPTAIL" = true ]; then
        if [ "$default_yes" = true ]; then
            whiptail --title "Uninstall" --yesno "$prompt" 14 74
        else
            whiptail --title "Uninstall" --defaultno --yesno "$prompt" 14 74
        fi
        return $?
    elif [ "$HAS_DIALOG" = true ]; then
        if [ "$default_yes" = true ]; then
            dialog --title "Uninstall" --yesno "$prompt" 14 74
        else
            dialog --title "Uninstall" --defaultno --yesno "$prompt" 14 74
        fi
        local rc=$?
        clear
        return $rc
    fi

    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n]: "
        default_response="y"
    else
        prompt="$prompt [y/N]: "
        default_response="n"
    fi

    read -p "$prompt" response
    response=${response:-$default_response}

    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        print_warn "Docker command not found - assuming already uninstalled"
        return 1
    fi

    if ! docker info &> /dev/null 2>&1; then
        print_warn "Docker daemon not running - some cleanup may be skipped"
        return 1
    fi

    return 0
}

check_sudo_early() {
    # Check if /opt/cambium-fiber-api exists and requires sudo to remove
    if [ -d "${INSTALL_DIR}" ]; then
        # To delete a directory, we need write permission on the PARENT directory
        PARENT_DIR=$(dirname "${INSTALL_DIR}")

        if [ ! -w "${PARENT_DIR}" ]; then
            print_info "Removing ${INSTALL_DIR} requires sudo privileges"

            # Test sudo access early
            if ! sudo -n true 2>/dev/null; then
                print_info "You may be prompted for your password..."
                echo ""

                if ! sudo -v; then
                    print_error "Failed to obtain sudo privileges"
                    print_error "Please run: sudo ./uninstall.sh"
                    exit 1
                fi
            fi

            print_info "Sudo access confirmed"
            echo ""
        fi
    fi
}

stop_and_remove_container() {
    print_info "Checking for running containers..."

    if ! check_docker; then
        print_warn "Skipping container removal (Docker not available)"
        return
    fi

    # Check if container exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_info "Stopping and removing container: ${CONTAINER_NAME}"

        # Stop container if running
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            docker stop "${CONTAINER_NAME}" > /dev/null 2>&1 || true
        fi

        # Remove container
        docker rm "${CONTAINER_NAME}" > /dev/null 2>&1 || true

        print_info "Container removed"
    else
        print_info "Container not found (already removed or never created)"
    fi

    # Check and remove orphaned volumes
    print_info "Checking for Docker volumes..."
    if docker volume ls --format '{{.Name}}' | grep -qE 'cambium.*api'; then
        for volume in $(docker volume ls --format '{{.Name}}' | grep -E 'cambium.*api'); do
            print_info "Removing volume: ${volume}"
            docker volume rm "${volume}" 2>/dev/null || true
        done
    fi
}

remove_docker_image() {
    if ! check_docker; then
        print_warn "Skipping image removal (Docker not available)"
        return
    fi

    # Check if image exists (any tag)
    if docker images --format '{{.Repository}}' | grep -q "^${IMAGE_NAME}$"; then
        print_info "Removing Docker images..."
        docker rmi $(docker images "${IMAGE_NAME}" --format "{{.Repository}}:{{.Tag}}") 2>/dev/null || true
        print_info "Docker image(s) removed"
    else
        print_info "No Docker images found for ${IMAGE_NAME}"
    fi
}

remove_data_directory() {
    if [ -d "${INSTALL_DIR}" ]; then
        print_info "Removing ${INSTALL_DIR}..."

        # To delete a directory, check if parent directory is writable
        PARENT_DIR=$(dirname "${INSTALL_DIR}")
        if [ -w "${PARENT_DIR}" ]; then
            rm -rf "${INSTALL_DIR}"
        else
            sudo rm -rf "${INSTALL_DIR}"
        fi

        print_info "Directory removed"
    else
        print_info "Installation directory not found (already removed or never created)"
    fi
}

print_summary() {
    echo ""
    print_info "================================================================"
    print_info "  Cambium Fiber API Uninstallation Complete"
    print_info "================================================================"
    echo ""
    print_info "Summary:"

    # Check what remains
    local remains_count=0

    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        print_warn "  ✗ Container still exists: ${CONTAINER_NAME}"
        remains_count=$((remains_count + 1))
    else
        print_info "  ✓ Container removed"
    fi

    if check_docker && docker images --format '{{.Repository}}' 2>/dev/null | grep -q "^${IMAGE_NAME}$"; then
        print_warn "  ✗ Docker image still exists: ${IMAGE_NAME}"
        remains_count=$((remains_count + 1))
    else
        print_info "  ✓ Docker image removed"
    fi

    if [ -d "${INSTALL_DIR}" ]; then
        print_warn "  ✗ Installation directory still exists: ${INSTALL_DIR}"
        remains_count=$((remains_count + 1))
    else
        print_info "  ✓ Installation directory removed"
    fi

    echo ""

    if [ $remains_count -eq 0 ]; then
        print_info "All components successfully removed"
    else
        print_warn "Some components were kept (by your choice or due to errors)"
    fi

    echo ""
    print_info "Docker Desktop was not affected by this uninstallation"
    print_info "================================================================"
}

# Main uninstallation flow
main() {
    echo ""
    print_info "Cambium Fiber API - Linux Uninstaller"
    print_info "======================================"
    echo ""

    # Detect installed version from .env or container label
    INSTALLED_VERSION="unknown"
    if [ -f "${INSTALL_DIR}/.env" ]; then
        _ver=$(grep '^APP_VERSION=' "${INSTALL_DIR}/.env" 2>/dev/null | head -1 | cut -d= -f2)
        [ -n "$_ver" ] && INSTALLED_VERSION="$_ver"
    fi

    if ! confirm "Are you sure you want to uninstall the Cambium Fiber API version ${INSTALLED_VERSION} container?\n\nTo reinstall follow the directions at\nhttps://github.com/cmbmwifi/cambium-fiber-api" "y"; then
        print_info "Uninstallation cancelled"
        exit 0
    fi

    echo ""
    # Check sudo early if needed
    check_sudo_early
    stop_and_remove_container
    remove_docker_image
    remove_data_directory
    print_summary
}

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        -y|--yes)
            YES_TO_ALL=true
            ;;
    esac
done

# Run main uninstallation
main
