#!/usr/bin/env python3

import json
import subprocess
import sys
from shutil import which

def check_xpu_smi():
    """Check if xpu-smi is available in PATH"""
    if not which('xpu-smi'):
        print("Error: xpu-smi not found. Please install Intel XPU manager.", file=sys.stderr)
        sys.exit(1)

def run_xpu_smi():
    """Run xpu-smi discovery and return parsed JSON data"""
    result = subprocess.run(['xpu-smi', 'discovery', '-j'], capture_output=True, text=True)
    return json.loads(result.stdout)

def get_gpu_devices():
    """Get comma-separated list of GPU device paths"""
    data = run_xpu_smi()
    devices = [dev['drm_device'] for dev in data['device_list'] if dev['device_type'] == 'GPU']
    return ','.join(devices)

def count_gpus():
    """Get number of available GPUs"""
    data = run_xpu_smi()
    return sum(1 for dev in data['device_list'] if dev['device_type'] == 'GPU')

def get_gpu_info():
    """Get detailed GPU information"""
    data = run_xpu_smi()
    gpu_info = []
    for dev in data['device_list']:
        if dev['device_type'] == 'GPU':
            gpu_info.append(f"{dev['device_id']}: {dev['device_name']} [{dev['drm_device']}]")
    return '\n'.join(gpu_info)

def main():
    check_xpu_smi()
    
    if len(sys.argv) != 2 or sys.argv[1] not in ['devices', 'count', 'info']:
        print(f"Usage: {sys.argv[0]} {{devices|count|info}}")
        print("  devices: Get comma-separated list of GPU device paths")
        print("  count:   Get number of available GPUs")
        print("  info:    Get detailed GPU information")
        sys.exit(1)

    command = sys.argv[1]
    if command == 'devices':
        print(get_gpu_devices())
    elif command == 'count':
        print(count_gpus())
    elif command == 'info':
        print(get_gpu_info())

if __name__ == '__main__':
    main()