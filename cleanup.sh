#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [model_directory]"
    echo "Examples:"
    echo "  $0                
    echo "  $0 Flan-Ul2    
    exit 1
fi

if [[ $# -eq 0 ]]; then
    MODEL_NAME="all"
    ENV_FILES=("${SCRIPT_DIR}"/models/*/config/model.env)
else
    MODEL_DIR="$1"
    MODEL_DIR="models/$MODEL_DIR"
    ENV_FILES=("${SCRIPT_DIR}/${MODEL_DIR}/config/model.env")
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

cleanup() {
    local exit_code=$?
    log "Starting cleanup process..."
    for ENV_FILE in "${ENV_FILES[@]}"; do
        if [[ -f "${ENV_FILE}" ]]; then
            set -a
            source "${ENV_FILE}"
            set +a

            if [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
                log "Stopping containers for ${MODEL_NAME}..."
                docker compose -f "${SCRIPT_DIR}/docker-compose.yml" --env-file "${ENV_FILE}" down --timeout 30 || true
            fi

            local containers=("${MODEL_NAME}" "tgi_auth" "tgi_proxy")
            for container in "${containers[@]}"; do
                if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
                    log "Force removing container ${container}..."
                    docker rm -f "${container}" || true
                fi
            done

            local network_name="${MODEL_NAME}_network"
            if docker network ls --format '{{.Name}}' | grep -q "^${network_name}$"; then
                log "Removing network ${network_name}..."
                docker network rm "${network_name}" || true
            fi
        fi
    done

    # Only try to kill processes if running as root
    if [ "$EUID" -eq 0 ]; then
        local ports=("8000" "3000")
        for port in "${ports[@]}"; do
            local pid
            pid=$(lsof -ti:"${port}" 2>/dev/null || true)
            if [[ -n "${pid}" ]]; then
                log "Cleaning up process using port ${port}..."
                kill -9 "${pid}" 2>/dev/null || true
            fi
        done
    fi

    log "Cleaning up dangling volumes..."
    docker volume prune -f || true

    if [ "$EUID" -ne 0 ]; then
        echo -e "\n\033[1;33m📌 Remote Access Tip:\033[0m"
        echo "If you're using SSH port forwarding, remember to remove"
        echo "'-L 8000:localhost:8000' from your SSH command"
    fi
    
    log "Cleanup completed"
    return $exit_code
}

trap cleanup EXIT
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cleanup
fi
