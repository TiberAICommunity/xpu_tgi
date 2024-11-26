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

info() {
    echo -e "\n\033[1;34m→ $1\033[0m"
}

ENV_FILE="${SCRIPT_DIR}/${MODEL_DIR}/config/model.env"
if [[ ! -f "${ENV_FILE}" ]]; then
    log "ERROR: model.env file not found at ${ENV_FILE}"
    exit 1
fi

set -a
source "${ENV_FILE}"
set +a

# Check for cloudflared process and stop it
if pgrep -f "cloudflared tunnel --url" >/dev/null; then
    info "Stopping Cloudflare tunnel..."
    pkill -f "cloudflared tunnel --url" || true
fi

if systemctl is-active --quiet "${MODEL_NAME}" 2>/dev/null; then
    if [ "$EUID" -ne 0 ]; then
        info "Notice: Service is running under systemd but script not run as root"
        echo -e "\033[1;33mTo stop the systemd service, either:\033[0m"
        echo "1. Run this script with sudo"
        echo "2. Manually stop with: sudo systemctl stop ${MODEL_NAME}"
        echo
    else
        log "Stopping systemd service ${MODEL_NAME}..."
        systemctl stop "${MODEL_NAME}" || true
        systemctl disable "${MODEL_NAME}" || true
        rm -f "/etc/systemd/system/${MODEL_NAME}.service" || true
        systemctl daemon-reload
        log "Systemd service ${MODEL_NAME} stopped and disabled"
    fi
fi

log "Running cleanup process..."
"${SCRIPT_DIR}/cleanup.sh" "${MODEL_DIR}"

info "Service stopped successfully"
echo -e "\n\033[1;33m📌 Remote Access Note:\033[0m"
echo "If you're accessing this server remotely, remember to update your SSH command"
echo "to remove any port forwarding (e.g., -L 8000:localhost:8000)"
