#!/usr/bin/env bash

# ==============================================================================
# Initialization Script for TGI Setup
# Checks for required dependencies and system configuration
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# -----------------------------
# Constants and Variables
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRED_PACKAGES=(
    "docker"
    "curl"
    "wget"
    "xpu-smi"
)

# -----------------------------
# Utility Functions
# -----------------------------
info() { echo -e "\n\033[1;34m→ $1\033[0m"; }
success() { echo -e "\n\033[1;32m✓ $1\033[0m"; }
error() { echo -e "\n\033[1;31m✗ $1\033[0m" >&2; exit 1; }
warning() { echo -e "\n\033[1;33m! $1\033[0m"; }


setup_jq() {
    info "Setting up JQ wrapper"    
    if command -v jq >/dev/null 2>&1; then
        success "Native jq found, using system installation"
        return 0
    fi
    
    info "Pulling official jq image"
    if ! docker pull ghcr.io/jqlang/jq:latest >/dev/null 2>&1; then
        error "Failed to pull jq Docker image"
    fi
    
    jq() {
        docker run --rm -i ghcr.io/jqlang/jq:latest "$@"
    }
    export -f jq
    if echo '{"test": "ok"}' | jq -r .test >/dev/null 2>&1; then
        success "Docker-based jq wrapper configured successfully"
    else
        error "Failed to setup jq wrapper"
    fi
}

# -----------------------------
# Check Functions
# -----------------------------
check_package() {
    local package=$1
    info "Checking for ${package}"
    case "${package}" in
        "docker")
            if ! command -v docker >/dev/null 2>&1; then
                error "Docker is not installed. Please install Docker first:
                    https://docs.docker.com/engine/install/"
            fi

            if ! docker info >/dev/null 2>&1; then
                error "Docker daemon is not running or current user doesn't have permission.
                    Run: sudo systemctl start docker
                    Add user to docker group: sudo usermod -aG docker \$USER"
            fi

            if ! docker compose version >/dev/null 2>&1; then
                error "Docker Compose plugin is not installed.
                    Install Docker Compose plugin:
                    https://docs.docker.com/compose/install/"
            fi
            ;;
            
        "xpu-smi")
            if ! command -v xpu-smi >/dev/null 2>&1; then
                error "Intel XPU-SMI is not installed. Please install Intel GPU drivers:
                    https://dgpu-docs.intel.com/installation-guides/"
            fi

            if ! xpu-smi discovery >/dev/null 2>&1; then
                error "No Intel GPUs detected. Please check GPU drivers and hardware."
            fi
            ;;
            
        *)
            if ! command -v "${package}" >/dev/null 2>&1; then
                error "${package} is not installed. Please install it using your package manager:
                    sudo apt-get install ${package}"
            fi
            ;;
    esac
    success "${package} is available"
}

check_system_resources() {
    info "Checking system resources"
    local total_mem
    total_mem=$(free -g | awk '/^Mem:/{print $2}')
    if [ "${total_mem}" -lt 16 ]; then
        warning "Less than 16GB RAM available (${total_mem}GB). This might affect performance."
    fi
    local free_space
    free_space=$(df -BG "${SCRIPT_DIR}" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "${free_space}" -lt 50 ]; then
        warning "Less than 50GB free disk space (${free_space}GB). Models require significant storage."
    fi
    success "System resource check completed"
}

check_gpu_configuration() {
    info "Checking GPU configuration"
    if [ ! -d "/dev/dri" ]; then
        error "GPU devices not found in /dev/dri"
    fi
    local gpu_info
    gpu_info=$(xpu-smi discovery 2>/dev/null)
    if [ -z "${gpu_info}" ]; then
        error "No Intel GPUs detected by xpu-smi"
    fi
    success "GPU configuration check completed"
}

check_token_configuration() {
    info "Checking authentication token"
    if [ -z "${VALID_TOKEN:-}" ]; then
        warning "VALID_TOKEN environment variable not set"
        echo "Please set the VALID_TOKEN environment variable:"
        echo "1. Generate token:    ./utils/generate_token.py"
        echo "2. Set environment:   export VALID_TOKEN=your_token"
        echo "3. Or add to shell:   echo 'export VALID_TOKEN=your_token' >> ~/.bashrc"
        error "Authentication token not configured"
    fi

    if ! [[ "${VALID_TOKEN}" =~ ^[A-Za-z0-9_-]+$ ]]; then
        error "Invalid token format. Token should contain only letters, numbers, underscores, and hyphens."
    fi
    success "Authentication token configured"
}

# -----------------------------
# Main Script
# -----------------------------
main() {
    info "Starting system initialization checks"
    check_token_configuration
    for package in "${REQUIRED_PACKAGES[@]}"; do
        check_package "${package}"
    done
    setup_jq  # use docker-based jq wrapper if jq not avaialble
    check_system_resources
    check_gpu_configuration
    success "All initialization checks passed successfully"
    echo -e "\nNext steps:"
    echo "1. Run ./setup_network.sh to create Docker network"
    echo "2. Run ./start_base.sh to start auth and proxy services"
    echo "3. Run ./add_model.sh <model_name> to add TGI services"
}

main 