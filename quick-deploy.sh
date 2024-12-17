#!/bin/bash

# oneliner
# curl -sSL https://raw.githubusercontent.com/tiberaicommunity/xpu_tgi/main/quick-deploy.sh | bash -s -- CodeLlama-7b

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

setup_dependencies() {
    echo -e "${GREEN}Setting up tools...${NC}"
    if ! command -v jq &>/dev/null; then
        echo "jq not found. Attempting to install..."
        if sudo apt-get update && sudo apt-get install -y jq; then
            echo "jq installed successfully"
        else
            echo "Could not install jq. Using Python fallback..."
            cat > "utils/pyjq.py" << 'EOF'
#!/usr/bin/env python3
import json
import sys
import argparse

def process_json(data, query):
    """Process JSON data with a jq-like query."""
    try:
        if isinstance(data, str):
            data = json.loads(data)
        if query == '.':
            return data
        elif query.startswith('.'):
            keys = query[1:].split('.')
            result = data
            for key in keys:
                if key:  # Skip empty keys from double dots
                    result = result[key]
            return result
        elif query == 'keys':
            return list(data.keys())
        elif query == 'length':
            return len(data)
        else:
            return data
    except Exception as e:
        print(f"Error processing JSON: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description='Python-based jq alternative')
    parser.add_argument('query', nargs='?', default='.')
    parser.add_argument('-r', '--raw-output', action='store_true', 
                       help='Output raw strings without quotes')
    args = parser.parse_args()
    try:
        input_data = sys.stdin.read().strip()
        if not input_data:
            sys.exit(0)
        result = process_json(input_data, args.query)
        if args.raw_output and isinstance(result, str):
            print(result)
        else:
            print(json.dumps(result, indent=2))
            
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
EOF
            chmod +x "utils/pyjq.py"
            jq() {
                "./utils/pyjq.py" "$@"
            }
            export -f jq
        fi
    fi
}

echo -e "${BLUE}
===========================================
 Intel XPU Text Generation Inference (TGI)
===========================================
${NC}
Quick deployment script for TGI on Intel GPUs
For custom configuration, visit: github.com/tiberaicommunity/xpu_tgi

This script will:
${GREEN}[*] Generate a secure authentication token
[*] Deploy the selected model ($1)
[*] Setup endpoints automatically${NC}
"

if [ $# -eq 0 ]; then
    echo -e "${RED}Error: No model specified${NC}"
    echo "Usage: $0 <model_name>"
    echo "Example: $0 CodeLlama-7b"
    exit 1
fi

MODEL_NAME="$1"
setup_dependencies

echo -e "${GREEN}Preparing deployment...${NC}"
if ! git clone https://github.com/tiberaicommunity/xpu_tgi 2>/dev/null; then
    if [ ! -d "xpu_tgi" ]; then
        echo -e "${RED}Error: Failed to clone repository${NC}"
        exit 1
    fi
fi

cd xpu_tgi || exit 1

echo -e "${GREEN}Setting up model cache...${NC}"
export HF_CACHE_DIR="${HOME}/.cache/huggingface"
mkdir -p "${HF_CACHE_DIR}"

echo -e "${GREEN}Generating secure token...${NC}"
export VALID_TOKEN=$(python3 -c "from utils.generate_token import generate_and_set; print(generate_and_set())")

# Create .auth_token_tgi_tgi.env file
echo "export VALID_TOKEN=${VALID_TOKEN}" > .auth_token_tgi_tgi.env
chmod 600 .auth_token_tgi_tgi.env
source .auth_token_tgi_tgi.env

echo -e "${GREEN}Token saved to .auth_token_tgi_tgi.env${NC}"

echo -e "${GREEN}Starting deployment...${NC}"
if ! ./deploy.sh "${MODEL_NAME}"; then
    echo -e "${RED}Deployment failed. Check the error messages above.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}=============== IMPORTANT ===============${NC}"
echo -e "${GREEN}Your authentication token has been generated and loaded.${NC}"
echo -e "${GREEN}Token is available as VALID_TOKEN in your current session.${NC}"
echo -e "\n${GREEN}To persist the token, add to your shell configuration:${NC}"
echo -e "${BLUE}echo 'export VALID_TOKEN=${VALID_TOKEN}' >> ~/.bashrc${NC}"
echo -e "${YELLOW}======================================${NC}\n"

echo -e "\n${YELLOW}============= NEXT STEPS ==============${NC}"
echo -e "${GREEN}1. Access Options:${NC}"
echo -e "   • Local machine: http://localhost:8000"
echo -e "   • Remote access: Run './tunnel.sh' for temporary public URL (eval only)"
echo -e "     (See './tunnel.sh --help' for options and security notes)"
echo -e "   • SSH tunnel: ssh -L 8000:localhost:8000 user@server"

echo -e "\n${GREEN}2. Test the deployment:${NC}"
echo -e "   ./tgi-status.sh"

echo -e "\n${GREEN}4. Stop the service:${NC}"
echo -e "   ./service_cleanup.sh --all     # Stop all services"
echo -e "   ./service_cleanup.sh --gpu N   # Stop specific GPU"
echo -e "${YELLOW}======================================${NC}\n"
