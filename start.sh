#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

ENABLE_TUNNEL=false
CACHE_MODELS=false
MODEL_DIR=""
SCRIPT_START_TIME=$(date +%s)
INTERVAL=10

show_help() {
    echo "Usage: $0 [OPTIONS] <model_directory>"
    echo
    echo "Start the TGI service with the specified model"
    echo
    echo "Options:"
    echo "  -h, --help         Show this help message"
    echo "  --remote-tunnel    Enable Cloudflare tunnel (FOR EVALUATION ONLY)"
    echo "  --cache-models     Cache models locally for faster reload"
    echo
    echo "Examples:"
    echo "  $0 Phi-3-mini"
    echo "  $0 --cache-models Phi-3-mini"
    echo "  $0 --remote-tunnel Phi-3-mini"
    echo
    echo "Note:"
    echo "  Model directory should be relative to ./models/"
    echo "  Use CTRL+C to gracefully stop the service"
    exit 0
}

cleanup_prompt() {
    echo -e "\n\n\033[1;33m⚠️  Shutdown requested\033[0m"
    echo -e "\nDo you want to clean up all services? (Y/n) "
    read -r response
    
    if [[ "$response" =~ ^[Nn]$ ]]; then
        echo -e "\n\033[1;33m📌 Note: Services are still running\033[0m"
        echo "To clean up later, run: ./cleanup.sh ${MODEL_DIR}"
        exit 0
    fi
    
    echo -e "\n\033[1;34m→ Cleaning up services...\033[0m"
    save_logs
    
    if [ "$ENABLE_TUNNEL" = true ] && [ -n "${TUNNEL_PID:-}" ]; then
        echo "Stopping Cloudflare tunnel..."
        kill $TUNNEL_PID 2>/dev/null || true
    fi
    
    if [ -n "${MODEL_NAME:-}" ]; then
        echo "Stopping containers..."
        docker compose -f "${SCRIPT_DIR}/docker-compose.yml" \
            --env-file "${ENV_FILE}" \
            --env-file "${ROOT_ENV_FILE}" \
            down --remove-orphans || true
    fi
    
    success "Cleanup completed"
    exit 0
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

info() {
    echo -e "\n\033[1;34m→ $1\033[0m"
}

success() {
    echo -e "\n\033[1;32m✓ $1\033[0m"
}

error() {
    echo -e "\n\033[1;31m❌ $1\033[0m"
    
    if [ -n "${MODEL_NAME:-}" ]; then
        save_logs
    fi
    
    cleanup_and_exit 1
}

save_logs() {
    local log_dir="${SCRIPT_DIR}/logs"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local start_time=${SCRIPT_START_TIME:-$(date +%s)}
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    mkdir -p "${log_dir}"
    
    echo -e "\n\033[1;33m📋 Saving service logs (Runtime: ${duration}s)\033[0m"
    
    {
        echo "=== Execution Summary ==="
        echo "Start time: $(date -d @${start_time} '+%Y-%m-%d %H:%M:%S')"
        echo "End time: $(date -d @${end_time} '+%Y-%m-%d %H:%M:%S')"
        echo "Total runtime: ${duration} seconds"
        if [ -n "${MODEL_NAME:-}" ]; then
            echo "Model: ${MODEL_NAME}"
        fi
        echo "======================="
    } > "${log_dir}/execution_${timestamp}.log"
    
    for service in "tgi_proxy" "tgi_auth" "${MODEL_NAME}"; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${service}$"; then
            echo -e "\n=== ${service} Logs ===" >> "${log_dir}/service_logs_${timestamp}.log"
            echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')" >> "${log_dir}/service_logs_${timestamp}.log"
            docker logs "${service}" &>> "${log_dir}/service_logs_${timestamp}.log"
            echo -e "\n=== End ${service} Logs ===\n" >> "${log_dir}/service_logs_${timestamp}.log"
        fi
    done
    
    {
        echo -e "\n=== Docker Compose Status ==="
        echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        docker compose -f "${SCRIPT_DIR}/docker-compose.yml" ps
        echo -e "\n=== Container Details ==="
        for service in "tgi_proxy" "tgi_auth" "${MODEL_NAME}"; do
            echo -e "\n${service}:"
            docker inspect "${service}" 2>/dev/null | grep -A 5 "State"
        done
    } >> "${log_dir}/service_logs_${timestamp}.log"
    
    echo -e "\033[1;32m✓ Logs saved to: ${log_dir}/service_logs_${timestamp}.log\033[0m"
}

setup_tunnel() {
    if [ "$ENABLE_TUNNEL" != true ]; then
        return
    }

    info "Setting up Cloudflare tunnel..."
    
    if ! command -v cloudflared &>/dev/null; then
        echo -e "\n\033[1;33m⚠️  Cloudflared not found, attempting to install...\033[0m"
        
        if command -v curl &>/dev/null; then
            curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
            sudo dpkg -i cloudflared.deb
            rm cloudflared.deb
        else
            error "curl not found. Please install cloudflared manually"
            return 1
        fi
    fi
    
    echo -e "\nStarting Cloudflare tunnel..."
    TUNNEL_URL_FILE=$(mktemp)
    cloudflared tunnel --url http://localhost:8000 2>&1 | while read -r line; do
        echo "$line"
        if [[ $line =~ "your url is: "(.+) ]]; then
            echo "${BASH_REMATCH[1]}" > "$TUNNEL_URL_FILE"
        fi
    done &
    
    TUNNEL_PID=$!
    local max_attempts=30
    local attempt=1
    
    echo -n "Waiting for tunnel to be ready"
    while [ ! -s "$TUNNEL_URL_FILE" ] && [ $attempt -lt $max_attempts ]; do
        echo -n "."
        sleep 1
        ((attempt++))
    done
    echo
    
    if [ ! -s "$TUNNEL_URL_FILE" ]; then
        error "Tunnel failed to start or provide URL"
        rm -f "$TUNNEL_URL_FILE"
        return 1
    fi
    
    TUNNEL_URL=$(cat "$TUNNEL_URL_FILE")
    rm -f "$TUNNEL_URL_FILE"
    
    success "Tunnel established successfully"
    echo -e "\n\033[1;34m📡 Tunnel Access Information:\033[0m"
    echo "→ Tunnel URL: $TUNNEL_URL"
    
    return 0
}


validate_model() {
    local model_dir="$1"
    local models_path="${SCRIPT_DIR}/models"
    
    if [ ! -d "${models_path}/${model_dir}" ]; then
        error "Model directory not found: ${model_dir}"
        echo -e "\nAvailable models:"
        ls -1 "${models_path}" 2>/dev/null || echo "No models found"
        exit 1
    }
    
    if [ ! -f "${models_path}/${model_dir}/config.json" ]; then
        error "Model configuration not found: ${model_dir}/config.json"
        exit 1
    }
}

prepare_environment() {
    local model_dir="$1"
    MODEL_NAME=$(basename "${model_dir}")
    info "Preparing environment for ${MODEL_NAME}..."
    ENV_FILE="${SCRIPT_DIR}/.env"
    ROOT_ENV_FILE="${SCRIPT_DIR}/../.env"
    if [ ! -f "${ROOT_ENV_FILE}" ]; then
        error "Root environment file not found: ${ROOT_ENV_FILE}"
        exit 1
    }
    
    {
        echo "MODEL_NAME=${MODEL_NAME}"
        echo "MODEL_PATH=/models/${model_dir}"
        if [ "$CACHE_MODELS" = true ]; then
            echo "CACHE_MODELS=true"
        fi
    } > "${ENV_FILE}"
    
    success "Environment prepared"
}

check_port_availability() {
    local port="$1"
    if lsof -i:"${port}" >/dev/null 2>&1; then
        error "Port ${port} is already in use"
        echo "Please stop any services using this port and try again"
        exit 1
    fi
}

wait_for_service() {
    local service="$1"
    local port="$2"
    local max_attempts=30
    local attempt=1
    
    echo -n "Waiting for ${service} to be ready..."
    
    while ! nc -z localhost "${port}" >/dev/null 2>&1; do
        if [ ${attempt} -eq ${max_attempts} ]; then
            echo -e "\n\033[1;31m❌ Service ${service} failed to start\033[0m"
            return 1
        fi
        echo -n "."
        sleep 1
        ((attempt++))
    done
    
    echo -e "\n\033[1;32m✓ Service ${service} is ready\033[0m"
    return 0
}
start_services() {
    info "Starting services..."
    
    check_port_availability 8000 
    docker compose -f "${SCRIPT_DIR}/docker-compose.yml" \
        --env-file "${ENV_FILE}" \
        --env-file "${ROOT_ENV_FILE}" \
        up -d

    if ! wait_for_service "${MODEL_NAME}" 80; then
        error "Model service failed to start"
        docker compose -f "${SCRIPT_DIR}/docker-compose.yml" logs
        exit 1
    fi
    
    if ! wait_for_service "tgi_auth" 3000; then
        error "Auth service failed to start"
        docker compose -f "${SCRIPT_DIR}/docker-compose.yml" logs
        exit 1
    fi
    
    if ! wait_for_service "tgi_proxy" 8000; then
        error "Proxy service failed to start"
        docker compose -f "${SCRIPT_DIR}/docker-compose.yml" logs
        exit 1
    fi
    
    success "All services started successfully"
}


monitor_services() {
    info "Monitoring services..."
    echo -e "\nPress Ctrl+C to stop the services"
    
    while true; do
        sleep "${INTERVAL}"
        for service in "tgi_proxy" "tgi_auth" "${MODEL_NAME}"; do
            if ! docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
                error "Service ${service} stopped unexpectedly"
                docker compose -f "${SCRIPT_DIR}/docker-compose.yml" logs
                exit 1
            fi
        done
    done
}

main() {

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                ;;
            --remote-tunnel)
                ENABLE_TUNNEL=true
                shift
                ;;
            --cache-models)
                CACHE_MODELS=true
                shift
                ;;
            *)
                if [ -n "${MODEL_DIR}" ]; then
                    error "Unexpected argument: $1"
                    exit 1
                fi
                MODEL_DIR="$1"
                shift
                ;;
        esac
    done
    
    if [ -z "${MODEL_DIR}" ]; then
        error "Model directory not specified"
        echo "Use -h or --help for usage information"
        exit 1
    fi
    

    trap cleanup_prompt SIGINT SIGTERM
    validate_model "${MODEL_DIR}"
    prepare_environment "${MODEL_DIR}"
    start_services
    if [ "$ENABLE_TUNNEL" = true ]; then
        setup_tunnel || true
    fi
    echo -e "\n\033[1;34m📡 Service Access Information:\033[0m"
    echo "→ Local URL: http://localhost:8080"
    if [ "$ENABLE_TUNNEL" = true ] && [ -n "${TUNNEL_PID:-}" ]; then
        echo "→ Tunnel URL: Check the cloudflared output above"
    fi
    echo -e "\n\033[1;33m⚠️  For evaluation purposes only. Do not use in production.\033[0m"
    monitor_services
}

main "$@"