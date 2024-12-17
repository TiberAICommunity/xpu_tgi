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
# Check Dependencies and Environment
# ------------------------------------------------------------------------------
if [ ! -f ".auth_token.env" ] && [ -z "${VALID_TOKEN}" ]; then
    echo "❌ Error: No authentication token found!"
    echo "Please either:"
    echo "  1. Run the TGI service first to create .auth_token.env"
    echo "  2. Set the VALID_TOKEN environment variable"
    exit 1
elif [ -f ".auth_token.env" ]; then
    source .auth_token.env
fi

if [ ! -d "simple_ui" ]; then
    echo "❌ Error: simple_ui directory not found"
    exit 1
fi

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
    health_response=$(curl -s -H "Authorization: Bearer $VALID_TOKEN" http://localhost:8000/health)
    info_response=$(curl -s -H "Authorization: Bearer $VALID_TOKEN" http://localhost:8000/info)

    if echo "$health_response" | grep -q "healthy" &&
        echo "$info_response" | grep -q "model_name"; then
        kill $LOADING_PID 2>/dev/null
        echo -e "\n✨ Model service is ready!"
        break
    else
        if [ $attempt -eq $max_attempts ]; then
            kill $LOADING_PID 2>/dev/null
            echo -e "\n❌ Timeout waiting for model service to be ready"
            echo "Please ensure the model service is properly started"
            echo "Health Response: $health_response"
            echo "Info Response: $info_response"
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