#!/usr/bin/env bash

# ==============================================================================
# Add Model Script for TGI
# This script adds a new TGI service using model configuration from models directory
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# -----------------------------
# Constants and Variables
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.tgi.yml"
SERVICE_LIST_FILE="${SCRIPT_DIR}/services.json"
ENV_FILE="${SCRIPT_DIR}/.env"
MODELS_DIR="${SCRIPT_DIR}/models"

# -----------------------------
# Cleanup Functions
# -----------------------------
cleanup() {
    local exit_code=$?
    
    # Only clean up if there was an error or interruption
    if [ $exit_code -ne 0 ]; then
        echo -e "\n\nCleaning up after error/interruption..."
        
        # Only clean up if we created a new container in this run
        if [ -n "${NEW_CONTAINER_CREATED:-}" ] && [ -n "${SERVICE_NAME:-}" ]; then
            local container_exists
            container_exists=$(docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" && echo "yes" || echo "no")
            
            if [ "${container_exists}" = "yes" ]; then
                echo "Stopping and removing container ${SERVICE_NAME}..."
                docker stop "${SERVICE_NAME}" 2>/dev/null || true
                docker rm "${SERVICE_NAME}" 2>/dev/null || true
            fi
        fi
        
        echo -e "\n\033[1;31m✗ Script failed or was interrupted. Cleanup completed.\033[0m"
    fi
    
    exit $exit_code
}

# Add trap for cleanup
trap cleanup INT TERM EXIT

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
validate_args() {
    info "Validating arguments"
    
    if [ $# -ne 1 ]; then
        error "Usage: $0 <model_name>"
    fi
    
    local input_name="$1"
    
    # Find the actual model directory name (case-insensitive)
    if [ ! -d "${MODELS_DIR}" ]; then
        error "Models directory not found: ${MODELS_DIR}"
    fi
    
    # Use find to locate the directory case-insensitively
    local found_model
    found_model=$(find "${MODELS_DIR}" -maxdepth 1 -type d -iname "${input_name}" -printf "%f\n" 2>/dev/null)
    
    if [ -z "${found_model}" ]; then
        error "Model directory not found: ${input_name}\nAvailable models:"
        ls -1 "${MODELS_DIR}" 2>/dev/null || echo "No models found in ${MODELS_DIR}"
    fi
    
    # Use the actual directory name (preserving original case)
    MODEL_NAME="${found_model}"
    MODEL_DIR="${MODELS_DIR}/${MODEL_NAME}"
    
    if [ ! -f "${MODEL_DIR}/config/model.env" ]; then
        error "Model configuration not found: ${MODEL_DIR}/config/model.env"
    fi
    
    info "Found model: ${MODEL_NAME}"
    success "Arguments validated"
}

validate_base_services() {
    info "Validating base services"
    
    # Check both services with health status
    for service in "tgi_proxy" "tgi_auth"; do
        if ! docker ps -q -f "name=${service}" >/dev/null 2>&1; then
            error "${service} service not running. Please run start_base.sh first"
        fi
        
        local health_status
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "${service}" 2>/dev/null || echo "unknown")
        if [ "${health_status}" != "healthy" ]; then
            error "${service} service is not healthy (status: ${health_status})"
        fi
    done
    
    success "Base services validation completed"
}

validate_gpu() {
    info "Validating GPU configuration"
    
    if [ ! -x "${SCRIPT_DIR}/utils/gpu_info.py" ]; then
        chmod +x "${SCRIPT_DIR}/utils/gpu_info.py"
    fi
    
    local gpu_count
    gpu_count=$("${SCRIPT_DIR}/utils/gpu_info.py" count)
    #echo "Debug: Found ${gpu_count} GPUs (0 to $((gpu_count-1)))"
    
    if [ "${gpu_count}" -eq 0 ]; then
        error "No Intel GPUs found. Please ensure Intel GPU drivers are installed and GPUs are available."
    fi
    local all_numbers
    all_numbers=$("${SCRIPT_DIR}/utils/gpu_info.py" numbers)
    #echo "Debug: Available GPU numbers: ${all_numbers}"
    IFS=',' read -ra ALL_GPUS <<< "${all_numbers}"    
    local used_gpus=","
    while read -r container; do
        if [ -n "${container}" ] && [[ "${container}" =~ _gpu([0-9]+) ]]; then
            local gpu_num="${BASH_REMATCH[1]}"
            used_gpus="${used_gpus}${gpu_num},"
            #echo "Debug: Found container using GPU ${gpu_num}: ${container}"
        fi
    done < <(docker ps --format '{{.Names}}' | grep "tgi_" | grep -v "tgi_proxy\|tgi_auth")
    #echo "Debug: GPUs in use: ${used_gpus#,}"
    

    local available_gpu=""
    for gpu in "${ALL_GPUS[@]}"; do
        if [ "${gpu}" -lt "${gpu_count}" ]; then  # Ensure GPU number is valid
            if [[ ! "${used_gpus}" =~ ,${gpu}, ]]; then
                available_gpu="${gpu}"
                break
            fi
        fi
    done
    
    if [ -z "${available_gpu}" ]; then
        error "No available GPUs found. All devices (0 to $((gpu_count-1))) are in use.\nTry stopping an existing model with: ./service_cleanup.sh --gpu <N>"
    fi
    
    export GPU_NUM="${available_gpu}"
    #echo "Debug [validate_gpu]: Setting GPU_NUM=${GPU_NUM}"
    info "Selected GPU number: ${GPU_NUM}"
    success "GPU validation completed"
}

# -----------------------------
# Model Setup Functions
# -----------------------------

setup_model_env() {
    info "Setting up model environment"
    #echo "Debug [setup_model_env start]: GPU_NUM=${GPU_NUM}"
    source "${MODEL_DIR}/config/model.env"
    #echo "Debug [after source]: GPU_NUM=${GPU_NUM}"
    if [ ! -x "${SCRIPT_DIR}/utils/name_sanitizer.py" ]; then
        chmod +x "${SCRIPT_DIR}/utils/name_sanitizer.py"
    fi
    
    local sanitized_output
    sanitized_output=$("${SCRIPT_DIR}/utils/name_sanitizer.py" "${MODEL_NAME}")
    SERVICE_NAME=$(echo "${sanitized_output}" | head -n1)
    local base_route=$(echo "${sanitized_output}" | tail -n1)
    ROUTE_PREFIX="${base_route%/generate}/gpu${GPU_NUM}/generate"
    
    export SERVICE_NAME
    export ROUTE_PREFIX
    export MODEL_NAME
    export MODEL_ID
    export TGI_VERSION
    export SHM_SIZE
    export SERVICE_PORT=8000
    export MAX_CONCURRENT_REQUESTS=${MAX_CONCURRENT_REQUESTS:-10}
    export MAX_BATCH_SIZE=${MAX_BATCH_SIZE:-8}
    export MAX_TOTAL_TOKENS=${MAX_TOTAL_TOKENS:-1000}
    export MAX_INPUT_LENGTH=${MAX_INPUT_LENGTH:-512}
    export MAX_WAITING_TOKENS=${MAX_WAITING_TOKENS:-100}
    export HF_CACHE_DIR=${HF_CACHE_DIR:-"/tmp/no_cache"}    
   
    if [ -z "${VALID_TOKEN}" ] && [ -f "${SCRIPT_DIR}/.env" ]; then
        source "${SCRIPT_DIR}/.env"
    fi
    
    if [ -z "${VALID_TOKEN}" ]; then
        error "VALID_TOKEN is not set"
    fi
    
    export RENDER_NUM=$((128 + GPU_NUM))
    #echo "Debug [setup_model_env end]: GPU_NUM=${GPU_NUM}, RENDER_NUM=${RENDER_NUM}"
    success "Model environment setup completed"
}

start_model_service() {
    info "Starting model service: ${MODEL_NAME}"
    #echo "Debug [start_model_service]: GPU_NUM=${GPU_NUM}, RENDER_NUM=${RENDER_NUM}"
    local project_name="tgi-gpu${GPU_NUM}"
    #echo "Debug: Environment variables:"
    #echo "SERVICE_NAME: ${SERVICE_NAME}"
    #echo "MODEL_NAME: ${MODEL_NAME}"
    echo "MODEL_ID: ${MODEL_ID}"
    #echo "TGI_VERSION: ${TGI_VERSION}"
    #echo "GPU_NUM: ${GPU_NUM}"
    echo "ROUTE_PREFIX: ${ROUTE_PREFIX}"
    echo "VALID_TOKEN: ${VALID_TOKEN:0:10}..."
    #echo "Project Name: ${project_name}"
    
    if [ "${DEBUG:-}" = "true" ]; then
        echo -e "\nFull docker-compose configuration:"
        COMPOSE_PROJECT_NAME="${project_name}" docker compose -f "${COMPOSE_FILE}" --env-file "${MODEL_DIR}/config/model.env" config
        echo -e "\nContinuing with service startup..."
    fi
    

    if ! COMPOSE_PROJECT_NAME="${project_name}" docker compose -f "${COMPOSE_FILE}" --env-file "${MODEL_DIR}/config/model.env" up -d; then
        error "Failed to start model service"
    fi
    
    success "Model service started successfully"
}


wait_for_model_service() {
    info "Waiting for model service to be healthy"
    
    local max_attempts=300  # 5 minutes (300 seconds)
    local attempt=1
    local last_log=""
    
    while [ $attempt -le $max_attempts ]; do
        local health_status
        health_status=$(docker inspect --format='{{.State.Status}}' "${SERVICE_NAME}" 2>/dev/null || echo "not_found")
        local current_log
        current_log=$(docker logs "${SERVICE_NAME}" 2>&1 | tail -n 1)
        if [ "${current_log}" != "${last_log}" ] && [ -n "${current_log}" ]; then
            echo -e "\nProgress: ${current_log}"
            last_log="${current_log}"
            if echo "${current_log}" | grep -q '"message":"Connected"'; then
                echo -e "\nModel service is ready!"
                success "Model service is connected and ready to use"
                return 0
            fi
        fi
        
        case "${health_status}" in
            "not_found")
                error "Service ${SERVICE_NAME} not found"
                ;;
            "exited"|"dead")
                echo -e "\nContainer logs:"
                docker logs "${SERVICE_NAME}" 2>&1 | tail -n 20
                error "Container stopped unexpectedly. Check logs above for details."
                ;;
            *)
                echo -n "."
                sleep 1
                attempt=$((attempt + 1))
                if [ $((attempt % 30)) -eq 0 ]; then
                    echo -e "\nStill waiting for model to be ready... (${attempt}/${max_attempts} seconds)"
                fi
                ;;
        esac
    done
    echo -e "\nTimeout reached. Last container logs:"
    docker logs "${SERVICE_NAME}" 2>&1 | tail -n 20
    error "Model service did not become ready within the timeout period (5 minutes)"
}

update_service_list() {
    info "Updating service list"
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local service_url="http://localhost:${SERVICE_PORT}${ROUTE_PREFIX}"
    local temp_file="${SERVICE_LIST_FILE}.tmp"
    jq --arg name "${SERVICE_NAME}" \
       --arg type "model" \
       --arg url "${service_url}" \
       --arg time "${timestamp}" \
       --arg model "${MODEL_NAME}" \
       '.services += [{
           name: $name,
           type: $type,
           url: $url,
           started_at: $time,
           model: $model
       }]' "${SERVICE_LIST_FILE}" > "${temp_file}"
    mv "${temp_file}" "${SERVICE_LIST_FILE}"
    
    success "Service list updated"
}

# -----------------------------
# Main Script
# -----------------------------
main() {
    info "Adding new TGI model service"
    
    validate_args "$@"
    validate_base_services
    validate_gpu
    setup_model_env
    start_model_service
    wait_for_model_service
    update_service_list
    
    success "Model service added successfully"
    echo -e "\nService Status:"
    echo "Model: ${MODEL_NAME}"
    echo "Service Name: ${SERVICE_NAME}"
    echo "URL: http://localhost:${SERVICE_PORT}${ROUTE_PREFIX}"
    echo -e "\nTo test the service:"
    echo "curl -X POST http://localhost:${SERVICE_PORT}${ROUTE_PREFIX} \\"
    echo "     -H \"Authorization: Bearer \${VALID_TOKEN}\" \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d '{\"inputs\":\"Hello, how are you?\"}'"
}

main "$@" 