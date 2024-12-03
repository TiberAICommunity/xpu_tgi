#!/usr/bin/env python3

import yaml
import argparse
import subprocess
from pathlib import Path
import json

def get_available_gpus():
    """Get list of available Intel GPUs using xpu-smi"""
    try:
        result = subprocess.run(['xpu-smi', 'discovery', '-j'], 
                              capture_output=True, 
                              text=True, 
                              check=True)

        devices = json.loads(result.stdout)
        gpus = []
        for device in devices.get('device_list', []):
            if device.get('device_type') == 'GPU':
                drm_device = device.get('drm_device', '')
                if drm_device.startswith('/dev/dri/card'):
                    gpu_id = int(drm_device.replace('/dev/dri/card', ''))
                    gpus.append({
                        'id': gpu_id,
                        'drm_device': drm_device,
                        'name': device.get('device_name'),
                        'device_id': device.get('device_id')
                    })
        
        print(f"Found GPUs: {json.dumps(gpus, indent=2)}")
        return [gpu['id'] for gpu in gpus]
        
    except subprocess.CalledProcessError as e:
        print(f"Error running xpu-smi: {e}")
        return []
    except json.JSONDecodeError as e:
        print(f"Error parsing xpu-smi output: {e}")
        return []
    except Exception as e:
        print(f"Unexpected error: {e}")
        return []

def load_base_compose():
    """Load the base single-GPU docker-compose.yml"""
    with open('docker-compose.yml', 'r') as f:
        return yaml.safe_load(f)

def format_command(cmd_list):
    """Format command with proper indentation and style"""
    return ' >\n      ' + '\n      '.join(cmd_list)

def format_healthcheck_test(test_list):
    """Format healthcheck test with proper array notation"""
    return [f'["CMD", {", ".join(repr(x) for x in test_list[1:])}]']

def format_labels(labels):
    """Format labels with proper quotation"""
    return [f'"{label}"' for label in labels]

def generate_tgi_service(gpu_id, base_tgi_config):
    """Generate TGI service configuration for a specific GPU"""
    service_name = f"tgi-gpu{gpu_id}" if gpu_id != -1 else "tgi"
    tgi_config = base_tgi_config.copy()
    
    # Update container name
    tgi_config['container_name'] = "${MODEL_NAME}_gpu" + str(gpu_id) if gpu_id != -1 else "${MODEL_NAME}"
    
    # Update device mapping
    tgi_config['devices'] = [f"/dev/dri/card{gpu_id}:/dev/dri/card{gpu_id}"]
    
    # Format command properly
    cmd_parts = [
        '--model-id ${MODEL_ID}',
        '--dtype bfloat16',
        '--max-concurrent-requests ${MAX_CONCURRENT_REQUESTS}',
        '--max-batch-size ${MAX_BATCH_SIZE}',
        '--max-total-tokens ${MAX_TOTAL_TOKENS}',
        '--max-input-length ${MAX_INPUT_LENGTH}',
        '--max-waiting-tokens ${MAX_WAITING_TOKENS}',
        '--cuda-graphs 0',
        '--port 80',
        '--json-output'
    ]
    tgi_config['command'] = format_command(cmd_parts)
    
    # Update labels for multi-GPU setup
    if gpu_id != -1:
        tgi_config['labels'] = format_labels([
            "traefik.enable=true",
            f"traefik.http.routers.tgi-gpu{gpu_id}.rule=PathPrefix(`/gpu{gpu_id}/generate`)",
            f"traefik.http.routers.tgi-gpu{gpu_id}.middlewares=chain-auth@file,strip-gpu{gpu_id}",
            f"traefik.http.middlewares.strip-gpu{gpu_id}.stripprefix.prefixes=/gpu{gpu_id}",
            f"traefik.http.services.tgi-gpu{gpu_id}.loadbalancer.server.port=80"
        ])
    
    # Format expose ports with quotes
    if 'expose' in tgi_config:
        tgi_config['expose'] = [f'"{port}"' for port in tgi_config['expose']]
    
    return tgi_config

def generate_compose_file(gpus=None):
    """Generate docker-compose file based on GPU selection"""
    base_compose = load_base_compose()
    available_gpus = get_available_gpus()
    
    if not gpus:
        return base_compose
    if gpus == [-1]:
        gpus = available_gpus

    for gpu in gpus:
        if gpu not in available_gpus:
            raise ValueError(f"GPU {gpu} not available. Available GPUs: {available_gpus}")
    new_compose = base_compose.copy()
    base_tgi_config = base_compose['services']['tgi']
    new_compose['services'].pop('tgi')
    for gpu_id in gpus:
        service_name = f"tgi-gpu{gpu_id}"
        new_compose['services'][service_name] = generate_tgi_service(gpu_id, base_tgi_config)
    
    return new_compose

class CustomDumper(yaml.Dumper):
    def increase_indent(self, flow=False, indentless=False):
        return super().increase_indent(flow, False)
    
    def represent_scalar(self, tag, value, style=None):
        if isinstance(value, str) and '\n' in value:
            style = '|'
        return super().represent_scalar(tag, value, style)

def write_compose_file(config, filename):
    """Write compose file with preserved formatting"""
    with open(filename, 'w') as f:
        yaml.dump(config, f, Dumper=CustomDumper, sort_keys=False, default_flow_style=False)

def main():
    parser = argparse.ArgumentParser(description='Generate docker-compose file for TGI services')
    parser.add_argument('--gpus', type=str, help='Comma-separated GPU IDs or -1 for all GPUs')
    args = parser.parse_args()
    
    gpus = None
    if args.gpus:
        gpus = [int(g.strip()) for g in args.gpus.split(',')]
    
    try:
        compose_config = generate_compose_file(gpus)
        output_file = 'docker-compose.multi-gpu.yml' if gpus else 'docker-compose.yml'
        write_compose_file(compose_config, output_file)
        print(f"Generated {output_file}")
        
    except Exception as e:
        print(f"Error: {str(e)}")
        exit(1)

if __name__ == "__main__":
    main()
