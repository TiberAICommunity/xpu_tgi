#!/usr/bin/env bash

# ==============================================================================
# TGI Status Script
# Shows status of all TGI services, URLs, and helpful commands
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

# -----------------------------
# Status Functions
# -----------------------------
show_base_services() {
    info "Base Services Status"

    if docker ps -q -f name="tgi_auth" >/dev/null 2>&1; then
        echo "Auth Service: Running ✓"
        echo "Health Check: $(docker inspect --format='{{.State.Health.Status}}' tgi_auth)"
    else
        echo "Auth Service: Not Running ✗"
    fi

    if docker ps -q -f name="tgi_proxy" >/dev/null 2>&1; then
        echo "Proxy Service: Running ✓"
        echo "Health Check: $(docker inspect --format='{{.State.Health.Status}}' tgi_proxy)"
        echo "Ports: $(docker port tgi_proxy 8000/tcp | tr '\n' ' ')"
    else
        echo "Proxy Service: Not Running ✗"
    fi

    echo -e "\n----------------------------------------"
}

show_model_services() {
    info "Model Services Status"

    echo "Running Model Services:"
    docker ps --filter "name=tgi_" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" |
        grep -v "tgi_auth\|tgi_proxy" || true

    echo -e "\nGPU Allocations:"
    docker ps -q --filter "name=tgi_" | while read -r container_id; do
        local container_name
        container_name=$(docker inspect --format='{{.Name}}' "$container_id" | sed 's/\///')
        if [[ $container_name != "tgi_auth" && $container_name != "tgi_proxy" ]]; then
            local gpu_num
            gpu_num=$(echo "${container_name}" | grep -o '_gpu[0-9]*' | cut -d'p' -f2)
            echo "- ${container_name} (GPU ${gpu_num}):"
            docker inspect --format='{{range .HostConfig.Devices}}  {{.PathOnHost}}{{"\n"}}{{end}}' "$container_id" | grep "/dev/dri"
        fi
    done

    echo -e "\n----------------------------------------"
}

show_service_urls() {
    info "Service URLs"

    if [ -f "${SERVICE_LIST_FILE}" ]; then
        echo "Active Endpoints:"
        docker ps --format '{{.Names}}' | grep "tgi_" | grep -v "tgi_auth\|tgi_proxy" | while read -r container; do
            if [[ $container =~ tgi_(.+)_gpu([0-9]+) ]]; then
                local model_name="${BASH_REMATCH[1]}"
                local gpu_num="${BASH_REMATCH[2]}"
                echo -e "\n- Model: ${model_name} (GPU ${gpu_num})"
                echo "  URL: http://localhost:8000/${model_name}/gpu${gpu_num}/generate"
            fi
        done
    else
        echo "No service list file found"
    fi

    echo -e "\n----------------------------------------"
}

show_helpful_commands() {
    info "Helpful Commands"

    print_help
}

print_help() {
    cat <<EOF

----------------------------------------

→ Helpful Commands
View logs:
  docker logs -f tgi_auth    # Auth service logs (follow mode)
  docker logs -f tgi_proxy   # Proxy service logs (follow mode)
  docker logs -f <model_container_name>  # Model service logs (follow mode)

Test a model (use route from status above):
  curl -X POST http://localhost:8000/MODEL_ROUTE/generate \\
       -H "Authorization: Bearer \${VALID_TOKEN}" \\
       -H 'Content-Type: application/json' \\
       -d '{"inputs":"Hello, how are you?"}'

Monitor GPU usage:
  xpu-smi dump -m18      # Show detailed GPU memory info
  xpu-smi -l            # Live monitoring mode
  xpu-smi discovery     # List available GPUs

Stop services:
  ./service_cleanup.sh --gpu <N>     # Stop model on specific GPU
  ./service_cleanup.sh --all         # Stop all services including base

----------------------------------------
EOF
}

# -----------------------------
# Main Script
# -----------------------------
main() {
    show_base_services
    show_model_services
    show_service_urls
    show_helpful_commands
}

main
