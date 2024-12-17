#!/bin/bash

# ==============================================================================
# Deploy Text Generation demo UI
# ==============================================================================
# This script deploys the Streamlit UI for the Chat service
# and optionally creates a public demo endpoint using Cloudflare Tunnel.
# ==============================================================================

set -e
echo "🎉🎉 Starting the chat UI service...🎉🎉"

# ------------------------------------------------------------------------------
# Install Dependencies
# ------------------------------------------------------------------------------
echo "📦 Installing UI dependencies..."
pip install streamlit requests pillow >/dev/null 2>&1

# ------------------------------------------------------------------------------
# Cleanup existing processes
# ------------------------------------------------------------------------------
echo "🧹 Cleaning up existing UI processes..."
pkill -f "streamlit run" || true
sleep 2

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
    echo "🔄 When the tunnel starts, click on the provided *.trycloudflare.com URL to access the UI"
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
