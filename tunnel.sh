#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

TUNNEL_PID=""
TUNNEL_URL=""

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Start a Cloudflare tunnel for TGI service"
    echo
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo "  --port PORT   Local port to tunnel (default: 8000)"
    echo
    echo "Note:"
    echo "  This is for EVALUATION PURPOSES ONLY"
    echo "  For production, use Cloudflare Zero Trust"
    exit 0
}

setup_cloudflared() {
    echo -e "\n\033[1;33m⚠️  CLOUDFLARE TUNNEL NOTICE:\033[0m"
    echo -e "\033[1;37m- This feature is for EVALUATION PURPOSES ONLY\033[0m"
    echo -e "\033[1;37m- For production use, please use Cloudflare Zero Trust\033[0m"
    echo -e "\033[1;37m- By continuing, you acknowledge this is not for production use\033[0m"
    echo -e "\nDo you wish to continue? (y/N) "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo -e "\n\033[1;33m📌 Alternative: Use SSH tunnel for remote access:\033[0m"
        echo "   ssh -L 8000:localhost:8000 user@server"
        exit 1
    fi

    if ! command -v cloudflared >/dev/null; then
        echo "Installing cloudflared..."
        curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
        sudo dpkg -i cloudflared.deb
        rm cloudflared.deb
    fi
}

cleanup() {
    if [ -n "${TUNNEL_PID:-}" ]; then
        echo -e "\n\033[1;34m→ Stopping tunnel...\033[0m"
        kill $TUNNEL_PID 2>/dev/null || true
    fi
    exit 0
}

trap cleanup SIGINT SIGTERM

main() {
    local port=8000

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                ;;
        esac
    done

    setup_cloudflared
    echo -e "\n\033[1;34m→ Starting Cloudflare tunnel...\033[0m"
    cloudflared tunnel --url "http://localhost:${port}" 2>&1 & TUNNEL_PID=$!
    echo -e "\n\033[1;33m📌 Tunnel is running. Press CTRL+C to stop.\033[0m"
    wait $TUNNEL_PID
}

main "$@" 