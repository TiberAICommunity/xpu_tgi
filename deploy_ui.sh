#!/bin/bash

# ==============================================================================
# Deploy Chat UI
# ==============================================================================
# This script deploys the Streamlit UI for the Chat service
# and optionally creates a public demo endpoint using Cloudflare Tunnel.
# ==============================================================================

set -e
echo "🎉🎉 Starting a demo UI for the chat service...🎉🎉"

# ------------------------------------------------------------------------------
# Check Arguments and Model Config
# ------------------------------------------------------------------------------
if [ $# -ne 1 ]; then
    echo "❌ Usage: $0 <model_name>"
    echo "Available models:"
    ls -1 models/
    exit 1
fi

MODEL_NAME=$1
MODEL_CONFIG="models/${MODEL_NAME}/config/model.env"

if [ ! -f "$MODEL_CONFIG" ]; then
    echo "❌ Error: Model configuration not found: $MODEL_CONFIG"
    echo "Available models:"
    ls -1 models/
    exit 1
fi

# Load model configuration
source "$MODEL_CONFIG"
echo -e "\n📚 Model Configuration Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏷️  Model Name: $MODEL_NAME"
echo "🤖 Model ID: $MODEL_ID"
echo "📝 Model Type: ${MODEL_TYPE:-TGI_LLM}"
echo "📊 Max Total Tokens: ${MAX_TOTAL_TOKENS:-1024}"
echo "📏 Max Input Length: ${MAX_INPUT_LENGTH:-512}"
echo "🔄 Max Concurrent Requests: ${MAX_CONCURRENT_REQUESTS:-1}"
echo "📦 Max Batch Size: ${MAX_BATCH_SIZE:-1}"
echo "🎯 TGI Version: ${TGI_VERSION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -e "\n🔍 Validating required environment variables..."
REQUIRED_VARS=("MODEL_NAME" "MODEL_ID" "MODEL_TYPE" "MAX_TOTAL_TOKENS" "MAX_INPUT_LENGTH")
MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -ne 0 ]; then
    echo "❌ Error: Missing required environment variables:"
    printf '%s\n' "${MISSING_VARS[@]}"
    exit 1
fi
echo "✅ All required environment variables are set"

# ------------------------------------------------------------------------------
# Check Auth Token
# ------------------------------------------------------------------------------
if [ ! -f ".auth_token.env" ] && [ -z "${VALID_TOKEN}" ]; then
    echo "❌ Error: No authentication token found!"
    echo "Please either:"
    echo "  1. Run the TGI service first to create .auth_token.env"
    echo "  2. Set the VALID_TOKEN environment variable"
    exit 1
fi

[ -f ".auth_token.env" ] && source .auth_token.env

export MODEL_NAME
export MODEL_ID
export MODEL_TYPE
export MAX_TOTAL_TOKENS
export MAX_INPUT_LENGTH

# ------------------------------------------------------------------------------
# Loading Animation Function
# ------------------------------------------------------------------------------
function show_loading_chat() {
    local frames=("💬" "💬 ." "💬 .." "💬 ..." "💬 ....")
    while true; do
        for frame in "${frames[@]}"; do
            echo -ne "\r$frame Waiting for model to load...   \r"
            sleep 0.2
        done
    done
}

# ------------------------------------------------------------------------------
# Wait for Model Service
# ------------------------------------------------------------------------------
echo "🔄 Starting model service initialization check..."
max_attempts=30
attempt=1

# Start loading animation in background
show_loading_chat &
LOADING_PID=$!
trap 'kill $LOADING_PID 2>/dev/null; exit' INT TERM EXIT

while [ $attempt -le $max_attempts ]; do
    echo -ne "\rAttempt $attempt/$max_attempts: Testing model endpoint..."
    
    # Test the generate endpoint with a minimal request
    test_response=$(curl -s -X POST \
        -H "Authorization: Bearer $VALID_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"inputs":"Hi","parameters":{"max_new_tokens":1}}' \
        "http://localhost:8000/${MODEL_NAME}/gpu0/generate")

    if echo "$test_response" | grep -q "generated_text"; then
        kill $LOADING_PID 2>/dev/null
        echo -e "\n✨ Model service is ready!"
        echo "📝 Test response: $test_response"
        break
    else
        if [ $attempt -eq $max_attempts ]; then
            kill $LOADING_PID 2>/dev/null
            echo -e "\n❌ Timeout waiting for model service to be ready"
            echo "Please ensure the model service is properly started"
            echo "Test Response: $test_response"
            exit 1
        fi
        sleep 2
        attempt=$((attempt + 1))
    fi
done
trap - INT TERM EXIT

# ------------------------------------------------------------------------------
# Cleanup existing processes
# ------------------------------------------------------------------------------
echo "🧹 Cleaning up existing UI processes..."
pkill -f "streamlit run" || true
sleep 2

# ------------------------------------------------------------------------------
# Install Dependencies
# ------------------------------------------------------------------------------
echo "📦 Installing UI dependencies..."
pip install streamlit requests pillow >/dev/null 2>&1

# ------------------------------------------------------------------------------
# Create chat history directory
# ------------------------------------------------------------------------------
echo "📁 Setting up chat history directory..."
mkdir -p chat_history

# ------------------------------------------------------------------------------
# Deploy UI
# ------------------------------------------------------------------------------
echo "🚀 Starting UI server..."
nohup streamlit run simple_ui/app.py >/dev/null 2>&1 &
UI_PID=$!
sleep 3

# ------------------------------------------------------------------------------
# Optional Tunnel Setup
# ------------------------------------------------------------------------------
echo -e "\n📡 Public Demo Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🌐 Create public demo endpoint via Cloudflare Tunnel? [y/N] \c"
read -r create_tunnel

if [[ $create_tunnel =~ ^[Yy]$ ]]; then
    echo -e "\n⚠️  NOTICE: For evaluation purposes only"
    echo "🔄 Starting Cloudflare tunnel..."

    # Check if cloudflared is installed
    if ! command -v cloudflared &>/dev/null; then
        echo "📥 Installing cloudflared..."
        curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb >/dev/null 2>&1
        sudo dpkg -i cloudflared.deb >/dev/null 2>&1
        rm cloudflared.deb
        echo "✅ Cloudflared installed successfully"
    fi
    echo "🚇 Starting tunnel for UI service..."
    trap 'kill $UI_PID 2>/dev/null || true' EXIT INT TERM
    cloudflared tunnel --url http://localhost:8501
else
    echo -e "\n🎉 UI Setup Complete!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🌐 Access the UI at: http://localhost:8501"
    echo "💡 Press Ctrl+C to stop the UI"

    trap 'kill $UI_PID 2>/dev/null || true' EXIT INT TERM
    wait $UI_PID
fi