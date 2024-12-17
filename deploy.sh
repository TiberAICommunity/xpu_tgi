#!/usr/bin/env bash

# ==============================================================================
# TGI Deployment Script
# One-step deployment for TGI services
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------
# Utility Functions
# -----------------------------
info() { echo -e "\n\033[1;34m→ $1\033[0m"; }
success() { echo -e "\n\033[1;32m✓ $1\033[0m"; }
error() {
    echo -e "\n\033[1;31m✗ $1\033[0m" >&2
    exit 1
}

# -----------------------------
# Validation Functions
# -----------------------------
check_gpu_availability() {
    info "Checking GPU availability"

    if [ ! -x "${SCRIPT_DIR}/utils/gpu_info.py" ]; then
        chmod +x "${SCRIPT_DIR}/utils/gpu_info.py"
    fi

    local gpu_count
    gpu_count=$("${SCRIPT_DIR}/utils/gpu_info.py" count)

    if [ "${gpu_count}" -eq 0 ]; then
        error "No available GPUs found"
    fi

    local used_gpus=","
    while read -r container; do
        if [ -n "${container}" ] && [[ "${container}" =~ _gpu([0-9]+) ]]; then
            local gpu_num="${BASH_REMATCH[1]}"
            used_gpus="${used_gpus}${gpu_num},"
        fi
    done < <(docker ps --format '{{.Names}}' | grep "tgi_" | grep -v "tgi_proxy\|tgi_auth")

    local all_numbers
    all_numbers=$("${SCRIPT_DIR}/utils/gpu_info.py" numbers)
    IFS=',' read -ra ALL_GPUS <<<"${all_numbers}"

    local has_available=false
    for gpu in "${ALL_GPUS[@]}"; do
        if [[ ! "${used_gpus}" =~ ,${gpu}, ]]; then
            has_available=true
            break
        fi
    done

    if [ "${has_available}" = "false" ]; then
        error "All GPUs are currently in use. Please free up a GPU first."
    fi

    success "GPU check completed"
}

# -----------------------------
# Service Check Functions
# -----------------------------
check_base_services() {
    info "Checking existing services..."

    # Check if auth and traefik are running
    if docker ps --format '{{.Names}}' | grep -q "tgi_auth" &&
        docker ps --format '{{.Names}}' | grep -q "tgi_proxy"; then
        return 0
    fi
    return 1
}

# -----------------------------
# Main Deployment Function
# -----------------------------
deploy() {
    local model_name="$1"

    info "Starting TGI deployment for model: ${model_name}"

    check_gpu_availability
    # Check if base services are running
    if check_base_services; then
        info "Base services already running, proceeding with model deployment"
    else
        info "Setting up base infrastructure..."

        info "Running system checks"
        if ! "${SCRIPT_DIR}/init.sh"; then
            error "System initialization failed. Try running './service_cleanup.sh' and try again."
        fi

        info "Setting up Docker network"
        if ! "${SCRIPT_DIR}/setup_network.sh"; then
            error "Network setup failed. Try running './service_cleanup.sh' and try again."
        fi

        info "Starting base services"
        if ! "${SCRIPT_DIR}/start_base.sh"; then
            error "Base services startup failed. Try running './service_cleanup.sh' and try again."
        fi
    fi

    info "Adding model service"
    if ! "${SCRIPT_DIR}/add_model.sh" "${model_name}"; then
        error "Model service deployment failed. Try running './service_cleanup.sh' and try again."
    fi

    success "Deployment completed successfully!"
}

# -----------------------------
# Main Script
# -----------------------------
main() {
    if [ $# -eq 1 ] && [[ "$1" == "-h" || "$1" == "--help" ]]; then
        usage
    fi

    if [ $# -ne 1 ]; then
        echo -e "${RED}Error: Invalid number of arguments${NC}"
        usage
    fi

    deploy "$1"
}

# -----------------------------
# Usage Function
# -----------------------------
usage() {
    cat <<EOF
Usage: $0 [OPTIONS] <model_name>

Deploy TGI services with a specified model.

Options:
    -h, --help     Show this help message

Example:
    $0 CodeLlama-7b         # For code generation
    $0 Flan-Ul2            # For general tasks
    $0 OpenHermes-Mistral  # For reasoning tasks
    
Available models:
$(ls -1 "${SCRIPT_DIR}/models" 2>/dev/null | grep -v "README.md" || echo "No models found in ${SCRIPT_DIR}/models")

Note: Requires available GPU. Use './service_cleanup.sh --gpu <N>' to free up a GPU if needed.
EOF
    exit 1
}

main "$@"
