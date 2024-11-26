#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

# Global variables
CACHE_MODELS=false
MODEL_DIR=""
SCRIPT_START_TIME=$(date +%s)
INTERVAL=5

# Function definitions
show_help() {
    echo "Usage: $0 [OPTIONS] <model_directory>"
    echo
    echo "Start the TGI service with the specified model"
    echo
    echo "Options:"
    echo "  -h, --help         Show this help message"
    echo "  --cache-models     Cache models locally for faster reload"
    echo
    echo "Examples:"
    echo "  $0 Phi-3-mini"
    echo "  $0 --cache-models Phi-3-mini"
    echo
    echo "Note:"
    echo "  Model directory should be relative to ./models/"
    echo "  Use CTRL+C to gracefully stop the service"
    echo "  For remote access, use: ./tunnel.sh after service is running"
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

show_api_preview() {
    echo -e "\n\033[1;33m📌 Once the service is ready, you can use it like this:\033[0m"
    echo -e "\033[1;37mEndpoint: \033[0mhttp://localhost:8000/generate"
    echo -e "\033[1;37mMethod:   \033[0mPOST"
    echo -e "\033[1;37mHeaders:  \033[0m"
    echo "  - Authorization: Bearer ${VALID_TOKEN}"
    echo "  - Content-Type: application/json"
    echo -e "\033[1;37mExample Request:\033[0m"
    echo "curl -X POST http://localhost:8000/generate \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -H 'Authorization: Bearer ${VALID_TOKEN}' \\"
    echo "  -d '{\"inputs\": \"What is the capital of France?\"}'"
    echo
    echo -e "\033[1;33m📌 Waiting for service to be ready...\033[0m"
}

show_api_documentation() {
    echo -e "\n\033[1;33m📌 API Usage Guide:\033[0m"
    echo -e "\033[1;37mEndpoint: \033[0mhttp://localhost:8000/generate"
    echo -e "\033[1;37mMethod:   \033[0mPOST"
    echo -e "\033[1;37mHeaders:  \033[0m"
    echo "  - Authorization: Bearer ${VALID_TOKEN}"
    echo "  - Content-Type: application/json"
    echo -e "\033[1;37mRequest Body:\033[0m"
    cat << 'EOF'
{
    "inputs": "What is the capital of France?",
    "parameters": {
        "max_new_tokens": 100,
        "temperature": 0.7,
        "top_p": 0.95,
        "repetition_penalty": 1.1
    }
}
EOF

    echo -e "\n\033[1;37mCURL Example:\033[0m"
    echo "curl -X POST http://localhost:8000/generate \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -H 'Authorization: Bearer ${VALID_TOKEN}' \\"
    echo "  -d '{\"inputs\": \"What is the capital of France?\", \"parameters\": {\"max_new_tokens\": 100}}'"

    echo -e "\n\033[1;33m📌 For remote access:\033[0m"
    echo "1. Use SSH tunnel:"
    echo "   ssh -L 8000:localhost:8000 user@server"
    echo
    echo "2. Or use Cloudflare tunnel:"
    echo "   ./tunnel.sh"
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
            docker logs "${service}" &>> "${log_dir}/service_logs_${timestamp}.log"
        fi
    done
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

cleanup_and_exit() {
    local exit_code=${1:-0}
    
    if [ -n "${MODEL_NAME:-}" ]; then
        echo "Stopping containers..."
        docker compose -f "${SCRIPT_DIR}/docker-compose.yml" \
            --env-file "${ENV_FILE}" \
            --env-file "${ROOT_ENV_FILE}" \
            down --remove-orphans || true
    fi
    
    exit "${exit_code}"
}

validate_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker is not installed. Please install Docker first."
    fi
    
    if ! docker info >/dev/null 2>&1; then
        error "Docker daemon is not running or current user doesn't have permission to access it."
    fi
}

check_port_available() {
    if lsof -i:8000 >/dev/null 2>&1; then
        error "Port 8000 is already in use. Please stop any running services on this port."
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

setup_model_cache() {
    info "Setting up model cache directory..."
    local cache_dir="${SCRIPT_DIR}/model_cache"
    mkdir -p "${cache_dir}"
    success "Model caching enabled at: ${cache_dir}"
}

check_service_ready() {
    for service in "tgi_auth" "tgi_proxy" "${MODEL_NAME}"; do
        if ! docker ps -q -f name="^${service}$" > /dev/null 2>&1; then
            return 1
        fi
        
        local health
        health=$(docker inspect --format='{{.State.Health.Status}}' "${service}" 2>/dev/null)
        if [ "$health" != "healthy" ]; then
            return 1
        fi
    done
    return 0
}

follow_tgi_logs() {
    local log_lines=0
    while true; do
        if ! docker ps -q -f name="^${MODEL_NAME}$" > /dev/null 2>&1; then
            error "TGI container stopped unexpectedly"
        fi
        
        # Get new log lines
        local new_logs
        new_logs=$(docker logs "${MODEL_NAME}" 2>&1 | tail -n +$((log_lines + 1)))
        if [[ -n "${new_logs}" ]]; then
            echo "${new_logs}"
            log_lines=$(docker logs "${MODEL_NAME}" 2>&1 | wc -l)
        fi
        
        # Check if service is ready
        if check_service_ready; then
            return 0
        fi
        sleep 2
    done
}

# Set up trap for CTRL+C and SIGTERM
trap cleanup_prompt SIGINT SIGTERM

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        --cache-models)
            CACHE_MODELS=true
            shift
            ;;
        -*)
            echo -e "\n\033[1;31m❌ Unknown option: $1\033[0m"
            if [[ "$1" == "--remote-tunnel" ]]; then
                echo -e "\n\033[1;33m📌 Note: Remote tunnel is now a separate script\033[0m"
                echo "First start the service:"
                echo "  VALID_TOKEN=xxx ./start.sh ${MODEL_DIR}"
                echo
                echo "Then start the tunnel:"
                echo "  ./tunnel.sh"
            fi
            echo
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

# Setup paths and validate
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Initial validations
validate_docker
check_port_available
validate_model_path

# Setup environment files
ROOT_ENV_FILE="${SCRIPT_DIR}/.env"
if [[ ! -f "${ROOT_ENV_FILE}" ]]; then
    error "ERROR: .env file not found at ${ROOT_ENV_FILE}"
fi

ENV_FILE="${SCRIPT_DIR}/${MODEL_DIR}/config/model.env"
if [[ ! -f "${ENV_FILE}" ]]; then
    error "ERROR: model.env file not found at ${ENV_FILE}"
fi

# Source the environment files
set -a
source "${ENV_FILE}"
source "${ROOT_ENV_FILE}"
set +a

# Validate required variables
for var in MODEL_NAME SHM_SIZE; do
    if [[ -z "${!var:-}" ]]; then
        error "ERROR: ${var} not set in ${ENV_FILE}"
    fi
done

if [ "$CACHE_MODELS" = true ]; then
    setup_model_cache
fi

# Start services
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

# Show API preview before logs
show_api_preview

info "This may take several minutes while the model downloads and loads..."
echo -e "\n\033[1;33m📌 TGI Service Logs:\033[0m"
if ! follow_tgi_logs; then
    error "Failed to start TGI service"
fi

success "🚀 Service is ready!"
show_api_documentation

exit 0