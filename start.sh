#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <model_directory>"
    echo "Example: $0 Flan-Ul2"
    exit 1
fi

MODEL_DIR="$1"
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

log "Waiting for service to be healthy..."
elapsed=0

while [ $elapsed -lt $MAX_WAIT ]; do
    UNHEALTHY_COUNT=$(docker compose -f "${SCRIPT_DIR}/docker-compose.yml" ps | grep -c "(unhealthy)" || true)
    HEALTH_STATUS=$(docker compose -f "${SCRIPT_DIR}/docker-compose.yml" ps | grep -c "healthy" || true)
    TOTAL_SERVICES=3  
    if [ "$UNHEALTHY_COUNT" -eq 0 ] && [ "$HEALTH_STATUS" -eq "$TOTAL_SERVICES" ]; then
        log "All services are healthy!"
        docker compose -f "${SCRIPT_DIR}/docker-compose.yml" \
            --env-file "${ENV_FILE}" \
            --env-file "${ROOT_ENV_FILE}" \
            ps
        exit 0
    fi

    if (( elapsed % 30 == 0 )); then
        log "Recent container logs:"
        docker compose -f "${SCRIPT_DIR}/docker-compose.yml" \
            --env-file "${ENV_FILE}" \
            --env-file "${ROOT_ENV_FILE}" \
            logs --tail=20
    fi

    sleep $INTERVAL
    elapsed=$((elapsed + INTERVAL))
    log "Still waiting for services to be healthy... ($elapsed/${MAX_WAIT}s)"
done

log "ERROR: Service failed to become healthy within ${MAX_WAIT} seconds"
log "Full container logs:"
docker compose -f "${SCRIPT_DIR}/docker-compose.yml" --env-file "${ENV_FILE}" logs
exit 1
