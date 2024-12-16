#!/usr/bin/env bash

# ==============================================================================
# Base Services Setup Script for TGI
# This script starts the authentication and proxy services
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# -----------------------------
# Constants and Variables
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.base.yml"
SERVICE_LIST_FILE="${SCRIPT_DIR}/services.json"

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
# Validation Functions
# -----------------------------
validate_files() {
    info "Validating required files"
    if [ ! -f "${COMPOSE_FILE}" ]; then
        error "Base services compose file not found: ${COMPOSE_FILE}"
    fi
    if ! docker compose -f "${COMPOSE_FILE}" config >/dev/null 2>&1; then
        error "Invalid compose file format: ${COMPOSE_FILE}"
    fi
    if [ ! -f "${SERVICE_LIST_FILE}" ]; then
        error "Service list file not found. Please run setup_network.sh first"
    fi
    if ! jq '.' "${SERVICE_LIST_FILE}" >/dev/null 2>&1; then
        error "Invalid JSON format in service list file"
    fi
    success "Required files validated"
}

validate_network() {
    info "Validating Docker network"
    local network_name="tgi_network"
    if ! docker network ls --format '{{.Name}}' | grep -q "^${network_name}$"; then
        error "TGI network not found. Please run setup_network.sh first"
    fi
    success "Network validation completed"
}

validate_docker() {
    info "Validating Docker environment"
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker is not installed. Please install Docker first."
    fi

    if ! docker info >/dev/null 2>&1; then
        error "Docker daemon is not running or current user doesn't have permission to access it."
    fi
    success "Docker validation completed"
}

check_port_available() {
    info "Checking port availability"
    if [ ! -x "${SCRIPT_DIR}/utils/port_check.py" ]; then
        chmod +x "${SCRIPT_DIR}/utils/port_check.py"
    fi
    local port_status
    port_status=$("${SCRIPT_DIR}/utils/port_check.py" check)
    if [ "${port_status}" != "available" ]; then
        echo "Port 8000 is already in use. Finding an alternative port..."
        local available_port
        available_port=$("${SCRIPT_DIR}/utils/port_check.py" find)
        if [ -z "${available_port}" ]; then
            error "No available ports found. Please free up a port."
        fi
        export SERVICE_PORT="${available_port}"
        echo "Using alternative port: ${SERVICE_PORT}"
    else
        export SERVICE_PORT=8000
        echo "Using default port: ${SERVICE_PORT}"
    fi
    success "Port validation completed"
}

# -----------------------------
# Service Management Functions
# -----------------------------
start_base_services() {
    info "Starting base services"
    if docker ps --format '{{.Names}}' | grep -q "^tgi_auth$\|^tgi_proxy$"; then
        error "Base services are already running. Please stop them first using service_cleanup.sh"
    fi
    if ! docker compose -f "${COMPOSE_FILE}" up -d --build; then
        error "Failed to start base services. Check ${COMPOSE_FILE} and logs"
    fi

    success "Base services started successfully"
}

wait_for_services() {
    info "Waiting for services to be healthy"

    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        local unhealthy=false
        for service in "tgi_auth" "tgi_proxy"; do
            local health_status
            health_status=$(docker inspect --format='{{.State.Health.Status}}' "${service}" 2>/dev/null || echo "not_found")

            case "${health_status}" in
            "healthy")
                continue
                ;;
            "not_found")
                error "Service ${service} not found"
                ;;
            *)
                unhealthy=true
                break
                ;;
            esac
        done

        if [ "${unhealthy}" = false ]; then
            success "All services are healthy"
            return 0
        fi

        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done

    error "Services did not become healthy within the timeout period"
}

update_service_list() {
    info "Updating service list"

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local base_url="http://localhost:${SERVICE_PORT}"
    local temp_file="${SERVICE_LIST_FILE}.tmp"
    if ! jq --arg timestamp "${timestamp}" \
        --arg base_url "${base_url}" \
        '.services += [
             {
               "name": "auth",
               "type": "base",
               "url": ($base_url + "/validate"),
               "started_at": $timestamp
             },
             {
               "name": "proxy",
               "type": "base",
               "url": $base_url,
               "started_at": $timestamp
             }
           ]' "${SERVICE_LIST_FILE}" >"${temp_file}"; then
        error "Failed to update service list JSON"
    fi

    mv "${temp_file}" "${SERVICE_LIST_FILE}"
    success "Service list updated"
}

# -----------------------------
# Main Script
# -----------------------------
main() {
    info "Starting TGI base services"

    validate_docker
    validate_network
    check_port_available
    validate_files
    if [ -z "${VALID_TOKEN:-}" ]; then
        error "VALID_TOKEN environment variable is not set"
    fi
    start_base_services
    wait_for_services
    update_service_list

    success "Base services setup completed successfully"
    echo -e "\nService Status:"
    echo "- Auth Service: http://localhost:${SERVICE_PORT}/validate"
    echo "- Proxy Service: http://localhost:${SERVICE_PORT}"
    echo -e "\nNext steps:"
    echo "Run ./add_model.sh <model_directory> to add TGI services"
}

main
