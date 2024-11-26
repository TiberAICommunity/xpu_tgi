#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

ENABLE_TUNNEL=false

# Parse arguments
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

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_handler() {
    local line_no=$1
    local error_code=$2
    log "ERROR: Command failed at line ${line_no} with exit code ${error_code}"
    
    if [ "$ENABLE_TUNNEL" = true ] && [ -n "${TUNNEL_PID:-}" ]; then
        kill $TUNNEL_PID 2>/dev/null || true
    fi
    
    docker compose -f "${SCRIPT_DIR}/docker-compose.yml" \
        --env-file "${ENV_FILE}" \
        --env-file "${ROOT_ENV_FILE}" \
        logs
    exit "${error_code}"
}

trap 'error_handler ${LINENO} $?' ERR

ROOT_ENV_FILE="${SCRIPT_DIR}/.env"
if [[ ! -f "${ROOT_ENV_FILE}" ]]; then
    log "ERROR: .env file not found at ${ROOT_ENV_FILE}"
    exit 1
fi

export $(grep VALID_TOKEN "${ROOT_ENV_FILE}")

if [[ -z "${VALID_TOKEN:-}" ]]; then
    log "ERROR: VALID_TOKEN not found in ${ROOT_ENV_FILE}"
    exit 1
fi

ENV_FILE="${SCRIPT_DIR}/${MODEL_DIR}/config/model.env"
if [[ ! -f "${ENV_FILE}" ]]; then
    log "ERROR: model.env file not found at ${ENV_FILE}"
    exit 1
fi

set -a
source "${ENV_FILE}"
set +a

setup_cloudflared() {
    echo -e "\n\033[1;33m⚠️  CLOUDFLARE TUNNEL NOTICE:\033[0m"
    echo -e "\033[1;37m- This feature is for EVALUATION PURPOSES ONLY\033[0m"
    echo -e "\033[1;37m- For production use, please use Cloudflare Zero Trust\033[0m"
    echo -e "\033[1;37m- By continuing, you acknowledge this is not for production use\033[0m"
    echo -e "\nDo you wish to continue? (y/N) "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Aborting tunnel setup"
        exit 1
    fi

    # Check if cloudflared is installed
    if ! command -v cloudflared >/dev/null; then
        echo "Installing cloudflared..."
        # Download and install the latest cloudflared
        curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
        sudo dpkg -i cloudflared.deb
        rm cloudflared.deb
    fi

    if ! sudo -n true 2>/dev/null; then
        echo -e "\n\033[1;33m📌 No sudo access detected!\033[0m"
        echo -e "\033[1;37mTo access the service from outside this machine:\033[0m"
        echo
        echo "Add the following to your existing SSH command:"
        echo "  -L 8000:localhost:8000"
        echo
        echo "Example: If your current SSH command is 'ssh user@server -p 2222'"
        echo "Change to: 'ssh user@server -p 2222 -L 8000:localhost:8000'"
        echo
        return 1
    fi
}

start_tunnel() {
    echo -e "\n\033[1;34m→ Starting Cloudflare tunnel...\033[0m"
    cloudflared tunnel --url http://localhost:8000 &
    TUNNEL_PID=$!
    
    # Wait for tunnel URL
    sleep 5
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
        echo -e "\n\033[1;31m❌ Failed to establish tunnel\033[0m"
    fi
}

if [ "$ENABLE_TUNNEL" = true ]; then
    setup_cloudflared
fi

validate_network() {
    local network_name="${MODEL_NAME}_network"

    log "Validating network configuration..."
    if docker network ls --format '{{.Name}}' | grep -q "^${network_name}$"; then
        log "Network ${network_name} exists, checking for conflicts..."
        local connected_containers
        connected_containers=$(docker network inspect "${network_name}" -f '{{range .Containers}}{{.Name}} {{end}}')
        if [[ -n "${connected_containers}" ]]; then
            log "WARNING: Network ${network_name} is being used by: ${connected_containers}"
            log "Cleaning up existing network..."
            docker compose -f "${SCRIPT_DIR}/docker-compose.yml" \
                --env-file "${ENV_FILE}" \
                --env-file "${ROOT_ENV_FILE}" \
                down --remove-orphans
        fi
    fi
}

log "Using configuration from: ${ENV_FILE}"
log "MODEL_NAME: ${MODEL_NAME}"
log "PORT: ${PORT}"
log "SHM_SIZE: ${SHM_SIZE}"
log "VALID_TOKEN is set: ${VALID_TOKEN:+yes}"

validate_network

log "Starting ${MODEL_NAME} service..."
export VALID_TOKEN
docker compose -f "${SCRIPT_DIR}/docker-compose.yml" \
    --env-file "${ENV_FILE}" \
    --env-file "${ROOT_ENV_FILE}" \
    up -d

check_service_ready() {
    # Check if all required containers are running
    local containers_running=true
    for service in "tgi_proxy" "tgi_auth" "${MODEL_NAME}"; do
        if ! docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
            containers_running=false
            break
        fi
    done

    # If containers are running, check TGI logs for model loaded message
    if [ "$containers_running" = true ]; then
        if docker logs "${MODEL_NAME}" 2>&1 | grep -q "Connected to pipeline"; then
            return 0
        fi
    fi
    return 1
}

info "Starting ${MODEL_NAME} service..."
info "This may take a few minutes while the model loads..."
elapsed=0

while [ $elapsed -lt $MAX_WAIT ]; do
    if check_service_ready; then
        echo -e "\n-------------------------------------------"
        success "🚀 Service is ready to accept requests!"
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

    if (( elapsed % 20 == 0 )); then
        echo -e "\n\033[1;30m--- Recent TGI Logs ---\033[0m"
        docker logs --tail=5 "${MODEL_NAME}" 2>&1 | grep -v "^time="
    fi

    sleep $INTERVAL
    elapsed=$((elapsed + INTERVAL))
    echo -ne "\r\033[1;34m⏳ Waiting for service to be ready... ($elapsed/${MAX_WAIT}s)\033[0m"
done

log "ERROR: Service failed to become ready within ${MAX_WAIT} seconds"
log "Full container logs:"
docker compose -f "${SCRIPT_DIR}/docker-compose.yml" --env-file "${ENV_FILE}" logs
exit 1
