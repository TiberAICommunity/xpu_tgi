#!/bin/bash

# oneliner
# curl -sSL https://raw.githubusercontent.com/tiberaicommunity/xpu_tgi/main/quick-deploy.sh | bash -s -- CodeLlama-7b

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

echo -e "${GREEN}Setting up tools...${NC}"
alias jq='docker run --rm -i ghcr.io/jqlang/jq:latest'
echo -e "${GREEN}Preparing deployment...${NC}"
if ! git clone https://github.com/tiberaicommunity/xpu_tgi 2>/dev/null; then
    if [ ! -d "xpu_tgi" ]; then
        echo -e "${RED}Error: Failed to clone repository${NC}"
        exit 1
    fi
fi

cd xpu_tgi || exit 1
echo -e "${GREEN}Generating secure token...${NC}"
export VALID_TOKEN=$(python3 -c "from utils.generate_token import generate_and_set; print(generate_and_set())")

echo -e "${GREEN}Starting deployment...${NC}"
if ! ./deploy.sh "$@"; then
    echo -e "${RED}Deployment failed. Check the error messages above.${NC}"
    exit 1
fi
