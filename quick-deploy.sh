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
    if ! command -v jq &> /dev/null; then
        echo "jq not found. Attempting to install..."
        if sudo apt-get update && sudo apt-get install -y jq; then
            echo "jq installed successfully"
        else
            echo "Could not install jq. Using container fallback..."
            alias jq='docker run --rm -i ghcr.io/jqlang/jq:latest'
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

TEMP_TOKEN_FILE=$(mktemp)
echo "export VALID_TOKEN=${VALID_TOKEN}" > "${TEMP_TOKEN_FILE}"
chmod 600 "${TEMP_TOKEN_FILE}"
source "${TEMP_TOKEN_FILE}"
rm "${TEMP_TOKEN_FILE}"

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
