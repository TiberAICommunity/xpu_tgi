#!/usr/bin/env bash

# ==============================================================================
# TGI Cleanup Script
# Safely stops and removes TGI services
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# -----------------------------
# Constants and Variables
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

confirm() {
    read -r -p "$1 [y/N] " response
    case "$response" in
    [yY][eE][sS] | [yY])
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}

# -----------------------------
# Cleanup Functions
# -----------------------------
stop_model_services() {
    info "Stopping model services"

    local model_containers
    model_containers=$(docker ps -q --filter "name=tgi_" | grep -v -E "tgi_auth|tgi_proxy" || true)

    if [ -n "${model_containers}" ]; then
        echo "Stopping containers:"
        echo "${model_containers}" | while read -r container; do
            local name
            name=$(docker inspect --format='{{.Name}}' "${container}" | sed 's/\///')
            echo "- ${name}"
            docker stop "${container}"
        done
        success "Model services stopped"
    else
        echo "No model services running"
    fi
}

stop_base_services() {
    info "Stopping base services"

    if docker ps -q -f name="tgi_auth" -f name="tgi_proxy" | grep -q .; then
        docker compose -f "${SCRIPT_DIR}/docker-compose.base.yml" down
        success "Base services stopped"
    else
        echo "No base services running"
    fi
}

remove_network() {
    info "Removing TGI network"

    if docker network ls | grep -q "tgi_network"; then
        docker network rm tgi_network
        success "Network removed"
    else
        echo "Network already removed"
    fi
}

cleanup_containers() {
    info "Cleaning up stopped containers"

    local stopped_containers
    stopped_containers=$(docker ps -aq --filter "name=tgi_")

    if [ -n "${stopped_containers}" ]; then
        echo "Removing containers:"
        echo "${stopped_containers}" | while read -r container; do
            local name
            name=$(docker inspect --format='{{.Name}}' "${container}" | sed 's/\///')
            echo "- ${name}"
            docker rm "${container}"
        done
        success "Containers removed"
    else
        echo "No containers to remove"
    fi
}

reset_service_list() {
    info "Resetting service list"

    if [ -f "${SERVICE_LIST_FILE}" ]; then
        rm "${SERVICE_LIST_FILE}"
        success "Service list removed"
    else
        echo "No service list to remove"
    fi
}

show_final_status() {
    info "Checking final status"

    local running_containers
    running_containers=$(docker ps --filter "name=tgi_" --format "{{.Names}}" || true)

    if [ -n "${running_containers}" ]; then
        error "Some containers are still running:\n${running_containers}"
    fi

    if docker network ls | grep -q "tgi_network"; then
        error "TGI network still exists"
    fi

    success "Cleanup completed successfully"
}

stop_specific_service() {
    local service_name="$1"
    info "Stopping service: ${service_name}"

    if docker ps -q -f "name=${service_name}" | grep -q .; then
        docker stop "${service_name}"
        docker rm "${service_name}"
        success "Service ${service_name} stopped and removed"

        # Update services.json to remove the service
        if [ -f "${SERVICE_LIST_FILE}" ]; then
            local temp_file="${SERVICE_LIST_FILE}.tmp"
            jq --arg name "${service_name}" '.services = [.services[] | select(.name != $name)]' "${SERVICE_LIST_FILE}" >"${temp_file}"
            mv "${temp_file}" "${SERVICE_LIST_FILE}"
        fi
    else
        error "Service ${service_name} not found"
    fi
}

stop_gpu_services() {
    local gpu_id="$1"
    info "Stopping services on GPU ${gpu_id}"

    local containers
    if [ "${gpu_id}" = "all" ]; then
        containers=$(docker ps --format '{{.Names}}' | grep "tgi_" | grep -v "tgi_proxy\|tgi_auth" || true)
    else
        containers=$(docker ps --format '{{.Names}}' | grep "tgi_.*_gpu${gpu_id}_[[:alnum:]]\+$" || true)
    fi

    if [ -n "${containers}" ]; then
        echo "Stopping containers:"
        echo "${containers}" | while read -r container; do
            echo "- ${container}"
            docker stop "${container}"
            docker rm "${container}"
            if [ -f "${SERVICE_LIST_FILE}" ]; then
                local temp_file="${SERVICE_LIST_FILE}.tmp"
                jq --arg name "${container}" '.services = [.services[] | select(.name != $name)]' "${SERVICE_LIST_FILE}" >"${temp_file}"
                mv "${temp_file}" "${SERVICE_LIST_FILE}"
            fi
        done
        success "GPU services stopped"
    else
        echo "No services running on GPU ${gpu_id}"
    fi
}

# -----------------------------
# Main Script
# -----------------------------
main() {
    if [ $# -eq 0 ]; then
        info "Starting full TGI services cleanup"

        if ! confirm "This will stop all TGI services and remove related containers. Continue?"; then
            echo "Cleanup cancelled"
            exit 0
        fi

        stop_model_services
        stop_base_services
        remove_network
        cleanup_containers
        reset_service_list
        show_final_status

    elif [ "$1" = "--gpu" ] && [ -n "${2:-}" ]; then
        if ! confirm "This will stop all services on GPU $2. Continue?"; then
            echo "Cleanup cancelled"
            exit 0
        fi
        stop_gpu_services "$2"

    elif [ "$1" = "--service" ] && [ -n "${2:-}" ]; then
        if ! confirm "This will stop service $2. Continue?"; then
            echo "Cleanup cancelled"
            exit 0
        fi
        stop_specific_service "$2"

    else
        echo "Usage:"
        echo "  $0                   # Full cleanup"
        echo "  $0 --gpu <id>        # Cleanup specific GPU services"
        echo "  $0 --service <name>  # Cleanup specific service"
        exit 1
    fi

    echo -e "\nTo start services again:"
    echo "1. ./setup_network.sh    # If network was removed"
    echo "2. ./start_base.sh       # If base services were stopped"
    echo "3. ./add_model.sh <model_name>"
}

main "$@"
