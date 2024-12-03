#!/usr/bin/env bash

set -euo pipefail

# Function to check if xpu-smi is available
check_xpu_smi() {
    if ! command -v xpu-smi &> /dev/null; then
        echo "Error: xpu-smi not found. Please install Intel XPU manager." >&2
        exit 1
    fi
}

get_gpu_devices() {
    local devices
    devices=$(xpu-smi discovery -j | jq -r '.device_list[] | select(.device_type=="GPU") | .drm_device' | tr '\n' ',' | sed 's/,$//')
    echo "${devices}"
}

count_gpus() {
    local count
    count=$(xpu-smi discovery -j | jq -r '.device_list[] | select(.device_type=="GPU") | .device_id' | wc -l)
    echo "${count}"
}

get_gpu_info() {
    local info
    info=$(xpu-smi discovery -j | jq -r '.device_list[] | select(.device_type=="GPU") | "\(.device_id): \(.device_name) [\(.drm_device)]"')
    echo "${info}"
}

case "${1:-}" in
    "devices")
        check_xpu_smi
        get_gpu_devices
        ;;
    "count")
        check_xpu_smi
        count_gpus
        ;;
    "info")
        check_xpu_smi
        get_gpu_info
        ;;
    *)
        echo "Usage: $0 {devices|count|info}"
        echo "  devices: Get comma-separated list of GPU device paths"
        echo "  count:   Get number of available GPUs"
        echo "  info:    Get detailed GPU information"
        exit 1
        ;;
esac 