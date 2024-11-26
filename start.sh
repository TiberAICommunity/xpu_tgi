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

setup_cloudflared() {
    echo -e "\n\033[1;33m⚠️  CLOUDFLARE TUNNEL NOTICE:\033[0m"
    echo -e "\033[1;37m- This feature is for EVALUATION PURPOSES ONLY\033[0m"
    echo -e "\033[1;37m- For production use, please use Cloudflare Zero Trust\033[0m"
    echo -e "\033[1;37m- By continuing, you acknowledge this is not for production use\033[0m"
    echo -e "\nDo you wish to continue? (y/N) "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo -e "\n\033[1;33m📌 Tunnel setup cancelled. You have these options:\033[0m"
        echo "1. Run without tunnel to access the service locally:"
        echo "   ./start.sh ${MODEL_DIR##*/}"
        echo
        echo "2. Use SSH tunnel for remote access:"
        echo "   ssh -L 8000:localhost:8000 user@server"
        echo
        return 1
    fi

    if ! sudo -n true 2>/dev/null; then
        echo -e "\n\033[1;31m❌ No sudo access detected!\033[0m"
        echo -e "\n\033[1;33m📌 You have these options:\033[0m"
        echo "1. Run without tunnel to access the service locally:"
        echo "   ./start.sh ${MODEL_DIR##*/}"
        echo
        echo "2. Use SSH tunnel for remote access:"
        echo "   ssh -L 8000:localhost:8000 user@server"
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
    if ! cloudflared tunnel --url http://localhost:8000 2>&1 & TUNNEL_PID=$!; then
        error "Failed to start Cloudflare tunnel"
    fi
    local max_attempts=30
    local attempt=0
    local tunnel_ready=false
    while [ $attempt -lt $max_attempts ]; do
        if TUNNEL_URL=$(cloudflared tunnel --url http://localhost:8000 2>&1); then
            echo "${TUNNEL_URL}" 
            if echo "${TUNNEL_URL}" | grep -q 'https://.*\.trycloudflare\.com'; then
                TUNNEL_URL=$(echo "${TUNNEL_URL}" | grep -o 'https://.*\.trycloudflare\.com')
                tunnel_ready=true
                break
            fi
        fi
        sleep 1
        ((attempt++))
    done
    
    if [ "$tunnel_ready" = true ]; then
        success "Tunnel established!"
    else
        error "Failed to establish tunnel"
    fi
}

setup_model_cache() {
    local cache_dir="${SCRIPT_DIR}/model_cache"
    info "Setting up model cache directory..."
    mkdir -p "${cache_dir}"
    export HF_CACHE_DIR="${cache_dir}"
    success "Model caching enabled at: ${cache_dir}"
}

check_model_env() {
    local model_path="$1"
    local env_file="${model_path}/config/model.env"
    
    if [[ ! -f "${env_file}" ]]; then
        echo -e "\n\033[1;31m❌ Model configuration not found!\033[0m"
        echo -e "\nExpected config file: ${env_file}"
        echo -e "\n\033[1;33m📌 Available models:\033[0m"
        
        if [ -d "models" ]; then
            local models_found=false
            for dir in models/*/; do
                if [ -f "${dir}config/model.env" ]; then
                    echo "  - $(basename "${dir}")"
                    models_found=true
                fi
            done
            
            if [ "$models_found" = false ]; then
                echo "  No configured models found"
            fi
        else
            echo "  No models directory found"
        fi
        
        echo -e "\n\033[1;37mTo add a new model:\033[0m"
        echo "1. Create directory: mkdir -p models/YOUR_MODEL_NAME/config"
        echo "2. Create config:    cp templates/model.env.template models/YOUR_MODEL_NAME/config/model.env"
        echo "3. Edit config:      nano models/YOUR_MODEL_NAME/config/model.env"
        echo
        exit 1
    fi
}

validate_model_path() {
    if [[ $MODEL_DIR != models/* ]]; then
        MODEL_DIR="models/$MODEL_DIR"
    fi
    
    info "Checking model path: ${SCRIPT_DIR}/${MODEL_DIR}"
    
    if [[ ! -d "${SCRIPT_DIR}/${MODEL_DIR}" ]]; then
        error "Model directory not found: ${SCRIPT_DIR}/${MODEL_DIR}"
    fi
    
    if [[ ! -f "${SCRIPT_DIR}/${MODEL_DIR}/config/model.env" ]]; then
        check_model_env "${SCRIPT_DIR}/${MODEL_DIR}"
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

trap cleanup_prompt SIGINT SIGTERM

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
        -*)
            echo "Unknown option: $1"
            show_help
            ;;
        *)
            MODEL_DIR="$1"
            shift
            ;;
    esac
done

if [[ -z "${MODEL_DIR}" ]]; then
    show_help
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validate_model_path

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

if [ "$ENABLE_TUNNEL" = true ]; then
    info "Setting up remote tunnel..."
    if ! setup_cloudflared; then
        exit 1
    fi
    
    info "Starting tunnel..."
    if ! start_tunnel; then
        echo -e "\n\033[1;31m❌ Failed to establish tunnel\033[0m"
        echo -e "\n\033[1;33m📌 You have these options:\033[0m"
        echo "1. Run without tunnel to access the service locally:"
        echo "   ./start.sh ${MODEL_DIR##*/}"
        echo
        echo "2. Use SSH tunnel for remote access:"
        echo "   ssh -L 8000:localhost:8000 user@server"
        echo
        exit 1
    fi
    
    success "Tunnel established at: ${TUNNEL_URL}"
fi

if [ "$CACHE_MODELS" = true ]; then
    setup_model_cache
fi

info "Starting deployment for ${MODEL_NAME}..."
log "Using configuration from: ${ENV_FILE}"
log "MODEL_NAME: ${MODEL_NAME}"
log "SHM_SIZE: ${SHM_SIZE}"
log "VALID_TOKEN is set: ${VALID_TOKEN:+yes}"

validate_network

info "Starting ${MODEL_NAME} service..."
if ! docker compose -f "${SCRIPT_DIR}/docker-compose.yml" \
    --env-file "${ENV_FILE}" \
    --env-file "${ROOT_ENV_FILE}" \
    up -d; then
    error "Failed to start services"
fi

info "This may take several minutes while the model downloads and loads..."

while true; do
    if check_service_ready; then
        success "🚀 Service is ready!"
        echo -e "\n\033[1;33m📌 Service Access Information:\033[0m"
        
        if [ "$ENABLE_TUNNEL" = true ] && [ -n "${TUNNEL_URL:-}" ]; then
            echo -e "\n\033[1;33m📌 Remote Access Information:\033[0m"
            echo -e "\033[1;37mEndpoint: \033[0m${TUNNEL_URL}/generate"
        else
            echo -e "\033[1;37mEndpoint: \033[0mhttp://localhost:8000/generate"
            echo -e "\n\033[1;33m📌 Remote Access Tip:\033[0m"
            echo "To access from outside this machine, append to your SSH command:"
            echo "  -L 8000:localhost:8000"
        fi
        
        echo -e "\033[1;37mMethod:   \033[0mPOST"
        echo -e "\033[1;37mHeaders:  \033[0m"
        echo "  - Authorization: Bearer ${VALID_TOKEN}"
        echo "  - Content-Type: application/json"
        
        if [ "$ENABLE_TUNNEL" = true ]; then
            echo -e "\n\033[1;31m⚠️  IMPORTANT: This tunnel is for evaluation only!\033[0m"
            wait $TUNNEL_PID
        fi
        exit 0
    fi
    sleep $INTERVAL
done

