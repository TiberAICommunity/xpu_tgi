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

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_handler() {
    local line_no=$1
    local error_code=$2
    log "ERROR: Command failed at line ${line_no} with exit code ${error_code}"
    exit "${error_code}"
}

trap 'error_handler ${LINENO} $?' ERR

ENV_FILE="${SCRIPT_DIR}/${MODEL_DIR}/config/model.env"
if [[ ! -f "${ENV_FILE}" ]]; then
    log "ERROR: model.env file not found at ${ENV_FILE}"
    exit 1
fi

set -a
source "${ENV_FILE}"
set +a

if systemctl is-active --quiet "${MODEL_NAME}"; then
    log "Stopping systemd service ${MODEL_NAME}..."
    if [ "$EUID" -ne 0 ]; then
        log "ERROR: Please run with sudo to stop systemd service"
        exit 1
    fi
    systemctl stop "${MODEL_NAME}" || true
    systemctl disable "${MODEL_NAME}" || true
    rm -f "/etc/systemd/system/${MODEL_NAME}.service" || true
    systemctl daemon-reload
    log "Systemd service ${MODEL_NAME} stopped and disabled"
fi

log "Running cleanup process..."
"${SCRIPT_DIR}/cleanup.sh" "${MODEL_DIR}"

log "Service stopped successfully"
