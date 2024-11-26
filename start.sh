#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

ENABLE_TUNNEL=false
MODEL_DIR=""
SCRIPT_START_TIME=$(date +%s)

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
    save_logs
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
        echo "Model: ${MODEL_NAME}"
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


cleanup_and_exit() {
    local exit_code=$1
    
    if [ "${exit_code}" -ne 0 ]; then
        save_logs
    fi
    
    if [ "$ENABLE_TUNNEL" = true ] && [ -n "${TUNNEL_PID:-}" ]; then
        kill $TUNNEL_PID 2>/dev/null || true
    fi
    
    if [ -n "${MODEL_NAME:-}" ]; then
        docker compose -f "${SCRIPT_DIR}/docker-compose.yml" \
            --env-file "${ENV_FILE}" \
            --env-file "${ROOT_ENV_FILE}" \
            down --remove-orphans || true
    fi
    
    exit "${exit_code}"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --remote-tunnel)
            ENABLE_TUNNEL=true
            shift
            ;;
        *)
            MODEL_DIR="$1"
            shift
            ;;
    esac
done

if [[ -z "${MODEL_DIR}" ]]; then
    echo "Usage: $0 [--remote-tunnel] <model_directory>"
    echo "Example: $0 Flan-Ul2"
    echo
    echo "Options:"
    echo "  --remote-tunnel    Enable Cloudflare tunnel (FOR EVALUATION ONLY)"
    exit 1
fi

MODEL_DIR="models/$MODEL_DIR"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAX_WAIT=600
INTERVAL=10

ROOT_ENV_FILE="${SCRIPT_DIR}/.env"
if [[ ! -f "${ROOT_ENV_FILE}" ]]; then
    error "ERROR: .env file not found at ${ROOT_ENV_FILE}"
fi

if ! VALID_TOKEN=$(grep -o '^VALID_TOKEN=.*' "${ROOT_ENV_FILE}" | cut -d= -f2); then
    error "ERROR: VALID_TOKEN not found in ${ROOT_ENV_FILE}"
fi
export VALID_TOKEN

ENV_FILE="${SCRIPT_DIR}/${MODEL_DIR}/config/model.env"
if [[ ! -f "${ENV_FILE}" ]]; then
    error "ERROR: model.env file not found at ${ENV_FILE}"
fi

set -a
if ! source "${ENV_FILE}"; then
    error "ERROR: Failed to source ${ENV_FILE}"
fi
set +a

for var in MODEL_NAME SHM_SIZE; do
    if [[ -z "${!var:-}" ]]; then
        error "ERROR: ${var} not set in ${ENV_FILE}"
    fi
done

setup_cloudflared() {
    echo -e "\n\033[1;33m⚠️  CLOUDFLARE TUNNEL NOTICE:\033[0m"
    echo -e "\033[1;37m- This feature is for EVALUATION PURPOSES ONLY\033[0m"
    echo -e "\033[1;37m- For production use, please use Cloudflare Zero Trust\033[0m"
    echo -e "\033[1;37m- By continuing, you acknowledge this is not for production use\033[0m"
    echo -e "\nDo you wish to continue? (y/N) "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Aborting tunnel setup"
        return 1
    fi

    if ! sudo -n true 2>/dev/null; then
        echo -e "\n\033[1;33m📌 No sudo access detected!\033[0m"
        echo -e "\033[1;37mTo access the service from outside this machine:\033[0m"
        echo
        echo "Add the following to your existing SSH command:"
        echo "  -L 8000:localhost:8000"
        echo
        return 1
    fi

    if ! command -v cloudflared >/dev/null; then
        echo "Installing cloudflared..."
        if ! curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb; then
            error "Failed to download cloudflared"
        fi
        if ! sudo dpkg -i cloudflared.deb; then
            rm -f cloudflared.deb
            error "Failed to install cloudflared"
        fi
        rm -f cloudflared.deb
    fi
    return 0
}

start_tunnel() {
    echo -e "\n\033[1;34m→ Starting Cloudflare tunnel...\033[0m"
    if ! cloudflared tunnel --url http://localhost:8000 & TUNNEL_PID=$!; then
        error "Failed to start Cloudflare tunnel"
    fi
    
    sleep 8
    TUNNEL_URL=$(cloudflared tunnel --url http://localhost:8000 2>&1 | grep -o 'https://.*\.trycloudflare\.com' || echo "")
    
    if [ -n "$TUNNEL_URL" ]; then
        echo -e "\n\033[1;32m✓ Tunnel established!\033[0m"
        echo -e "\033[1;33m📌 Remote Access Information:\033[0m"
        echo -e "\033[1;37mEndpoint: \033[0m${TUNNEL_URL}/generate"
        echo -e "\033[1;37mMethod:   \033[0mPOST"
        echo -e "\033[1;37mHeaders:  \033[0m"
        echo "  - Authorization: Bearer ${VALID_TOKEN}"
        echo "  - Content-Type: application/json"
        echo -e "\n\033[1;31m⚠️  IMPORTANT: This tunnel is for evaluation only!\033[0m"
    else
        error "Failed to establish tunnel"
    fi
}

validate_network() {
    local network_name="${MODEL_NAME}_network"

    log "Validating network configuration..."
    if docker network ls --format '{{.Name}}' | grep -q "^${network_name}$"; then
        log "Network ${network_name} exists, checking for conflicts..."
        local connected_containers
        connected_containers=$(docker network inspect "${network_name}" -f '{{range .Containers}}{{.Name}} {{end}}' || echo "")
        if [[ -n "${connected_containers}" ]]; then
            log "WARNING: Network ${network_name} is being used by: ${connected_containers}"
            log "Cleaning up existing network..."
            if ! docker compose -f "${SCRIPT_DIR}/docker-compose.yml" \
                --env-file "${ENV_FILE}" \
                --env-file "${ROOT_ENV_FILE}" \
                down --remove-orphans; then
                error "Failed to clean up existing network"
            fi
        fi
    fi
}

trap 'cleanup_and_exit $?' ERR

info "Starting deployment for ${MODEL_NAME}..."
log "Using configuration from: ${ENV_FILE}"
log "MODEL_NAME: ${MODEL_NAME}"
log "SHM_SIZE: ${SHM_SIZE}"
log "VALID_TOKEN is set: ${VALID_TOKEN:+yes}"

if [ "$ENABLE_TUNNEL" = true ]; then
    if ! setup_cloudflared; then
        ENABLE_TUNNEL=false
        info "Continuing without tunnel setup..."
    fi
fi

validate_network

info "Starting ${MODEL_NAME} service..."
if ! docker compose -f "${SCRIPT_DIR}/docker-compose.yml" \
    --env-file "${ENV_FILE}" \
    --env-file "${ROOT_ENV_FILE}" \
    up -d; then
    error "Failed to start services"
fi

check_service_ready() {
    # First check if auth and proxy are running and healthy
    for service in "tgi_auth" "tgi_proxy"; do
        if ! docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
            return 1
        fi
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "${service}" 2>/dev/null)
        if [ "$health_status" != "healthy" ]; then
            return 1
        fi
    done

    # Then check if TGI container is running and model is loaded
    if ! docker ps --format '{{.Names}}' | grep -q "^${MODEL_NAME}$"; then
        return 1
    fi

    # Show TGI logs continuously
    docker logs --tail=5 --follow "${MODEL_NAME}" 2>&1 | grep -v "^time=" &
    LOGS_PID=$!

    # Check TGI logs for model loading completion
    if docker logs "${MODEL_NAME}" 2>&1 | grep -q "Connected to pipeline"; then
        kill $LOGS_PID 2>/dev/null || true
        return 0
    fi

    return 1
}

info "Starting ${MODEL_NAME} service..."
info "This may take several minutes while the model downloads and loads..."

while true; do
    if check_service_ready; then
        success "🚀 Service is ready!"
        echo -e "\n\033[1;33m📌 Service Access Information:\033[0m"
        echo -e "\033[1;37mEndpoint: \033[0mhttp://localhost:8000/generate"
        echo -e "\033[1;37mMethod:   \033[0mPOST"
        echo -e "\033[1;37mHeaders:  \033[0m"
        echo "  - Authorization: Bearer ${VALID_TOKEN}"
        echo "  - Content-Type: application/json"
        
        if [ "$ENABLE_TUNNEL" = false ]; then
            echo -e "\n\033[1;33m📌 Remote Access Tip:\033[0m"
            echo "To access from outside this machine, append to your SSH command:"
            echo "  -L 8000:localhost:8000"
        fi
        
        if [ "$ENABLE_TUNNEL" = true ]; then
            start_tunnel
        fi
        exit 0
    fi
    sleep $INTERVAL
done

error "Service failed to become ready within ${MAX_WAIT} seconds"

