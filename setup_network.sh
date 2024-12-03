#!/usr/bin/env bash

# ==============================================================================
# Network Setup Script for TGI Services
# This script creates the shared Docker network for all TGI services
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# -----------------------------
# Constants and Variables
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NETWORK_NAME="tgi_network"
SERVICE_LIST_FILE="${SCRIPT_DIR}/services.json"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.network.yml"

# -----------------------------
# Utility Functions
# -----------------------------
info() {
    echo -e "\n\033[1;34m→ $1\033[0m"
}

success() {
    echo -e "\n\033[1;32m✓ $1\033[0m"
}

error() {
    echo -e "\n\033[1;31m✗ $1\033[0m" >&2
    exit 1
}

# -----------------------------
# Network Management Functions
# -----------------------------
create_network() {
    info "Creating Docker network"
    
    # Check if network already exists
    if docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then
        info "Network ${NETWORK_NAME} already exists"
        return 0
    fi
    
    # Create network directly
    if ! docker network create --driver bridge "${NETWORK_NAME}" 2>/dev/null; then
        error "Failed to create network: ${NETWORK_NAME}"
    fi
    
    # Verify network creation
    if ! docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then
        error "Network creation failed: ${NETWORK_NAME} not found"
    fi
    
    success "Network setup completed"
}

initialize_service_list() {
    info "Initializing service list"
    
    if [ ! -f "${SERVICE_LIST_FILE}" ]; then
        # Use proper JSON formatting and error handling
        if ! echo '{
            "network": "'${NETWORK_NAME}'",
            "created_at": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",
            "services": []
        }' | jq '.' > "${SERVICE_LIST_FILE}" 2>/dev/null; then
            error "Failed to create service list file with valid JSON"
        fi
        success "Service list initialized at ${SERVICE_LIST_FILE}"
    else
        # Validate existing JSON
        if ! jq '.' "${SERVICE_LIST_FILE}" >/dev/null 2>&1; then
            error "Existing service list file contains invalid JSON"
        fi
        info "Service list already exists at ${SERVICE_LIST_FILE}"
    fi
}

# -----------------------------
# Validation Functions
# -----------------------------
validate_files() {
    info "Validating required files"
    
    if [ ! -f "${COMPOSE_FILE}" ]; then
        error "Network compose file not found: ${COMPOSE_FILE}"
    fi
    
    # Validate compose file format
    if ! docker compose -f "${COMPOSE_FILE}" config >/dev/null 2>&1; then
        error "Invalid compose file format: ${COMPOSE_FILE}"
    fi
    
    success "Required files validated"
}

# -----------------------------
# Main Script
# -----------------------------
main() {
    info "Setting up TGI network infrastructure"
    
    # Validate required files
    validate_files
    
    # Create network using docker-compose
    create_network
    
    # Initialize service list file
    initialize_service_list
    
    success "Network setup completed successfully"
    echo -e "\nNext steps:"
    echo "1. Run ./start_base.sh to start auth and proxy services"
    echo "2. Run ./add_model.sh <model_directory> to add TGI services"
}

main 