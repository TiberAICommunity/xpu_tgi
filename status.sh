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
ENV_FILE="${SCRIPT_DIR}/${MODEL_DIR}/config/model.env"
if [[ ! -f "${ENV_FILE}" ]]; then
    log "ERROR: model.env file not found at ${ENV_FILE}"
    exit 1
fi

set -a
source "${ENV_FILE}"
set +a

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_network_status() {
    local network_name="${MODEL_NAME}_network"

    log "Checking network status..."
    if docker network ls --format '{{.Name}}' | grep -q "^${network_name}$"; then
        log "Network ${network_name} exists"
        log "Network details:"
        docker network inspect "${network_name}" -f '
Network ID: {{.Id}}
Name: {{.Name}}
Driver: {{.Driver}}
Containers connected: {{range .Containers}}
  - {{.Name}} ({{.IPv4Address}}){{end}}'
    else
        log "WARNING: Network ${network_name} does not exist"
        return 1
    fi
}

check_port_status() {
    local port="$1"
    if ss -tuln | grep -q ":${port}\b"; then
        log "Port ${port} is listening"
    else
        log "WARNING: Port ${port} is not listening"
    fi
}

log "Checking service status..."
if ! docker compose -f "${SCRIPT_DIR}/docker-compose.yml" --env-file "${ENV_FILE}" ps --format json > /dev/null 2>&1; then
    log "Service is not running"
    exit 1
fi

docker compose -f "${SCRIPT_DIR}/docker-compose.yml" --env-file "${ENV_FILE}" ps
check_network_status
check_port_status "8000"
check_port_status "${PORT}"
log "Resource usage:"
docker stats --no-stream $(docker compose -f "${SCRIPT_DIR}/docker-compose.yml" --env-file "${ENV_FILE}" ps -q)
log "Recent logs:"
docker compose -f "${SCRIPT_DIR}/docker-compose.yml" --env-file "${ENV_FILE}" logs --tail=20
