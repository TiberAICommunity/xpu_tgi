# TGI Models Collection

Welcome to `xpu_tgi`! 🚀  

A curated collection of Text Generation Inference (TGI) models optimized for Intel XPU, with built-in token based request handling and traffic management.

<div align="center">
<img src="./hi_tgi.jpg" alt="TGI LLM Servers" width="400"/>
</div>

> 🚀 **TL;DR - Quick Deploy**
```bash
curl -sSL https://raw.githubusercontent.com/tiberaicommunity/xpu_tgi/main/quick-deploy.sh | bash -s -- CodeLlama-7b
```

## Quick Start

### Option 1: One-Line Deployment
```bash
# Deploy with a single command
curl -sSL https://raw.githubusercontent.com/tiberaicommunity/xpu_tgi/main/quick-deploy.sh | bash -s -- CodeLlama-7b
```

### Option 2: Standard Deployment
```bash
# 1. Generate authentication token
export VALID_TOKEN=$(./utils/generate_token.py)

# 2. Deploy model
./deploy.sh CodeLlama-7b

# 3. Check status
./tgi-status.sh
```

### Option 3: Step-by-Step Deployment
```bash
# 1. Check system requirements
./init.sh

# 2. Setup network
./setup_network.sh

# 3. Start base services
./start_base.sh

# 4. Add model
./add_model.sh CodeLlama-7b
```

> ⚠️ **Important**: The `VALID_TOKEN` environment variable must be set before starting the service. This token will be used for authentication.

## Model Caching

### Enable Model Caching
Models can be cached locally for faster reload times:

```bash
# Start with caching enabled
./start.sh --cache-models your-model-name

# Cache location: ./model_cache/
```

Benefits of caching:
- 🚀 Faster model reloads
- 📉 Reduced bandwidth usage
- 🔄 Persistent across restarts
- 💾 Shared cache across models

> Note: Ensure sufficient disk space is available for caching large models

## Architecture & Security

```mermaid
flowchart LR
    Client([Client])
    Traefik[Traefik Proxy]
    Auth[Auth Service]
    TGI[TGI Service]

    Client --> Traefik
    Traefik --> Auth
    Auth --> Traefik
    Traefik --> TGI
    TGI --> Traefik
    Traefik --> Client

    subgraph Internal["Internal Network"]
        Traefik
        Auth
        TGI
    end

    classDef client fill:#f2d2ff,stroke:#9645b7,stroke-width:2px;
    classDef proxy fill:#bbdefb,stroke:#1976d2,stroke-width:2px;
    classDef auth fill:#c8e6c9,stroke:#388e3c,stroke-width:2px;
    classDef tgi fill:#ffccbc,stroke:#e64a19,stroke-width:2px;
    classDef network fill:#fff9c4,stroke:#fbc02d,stroke-width:1px;

    class Client client;
    class Traefik proxy;
    class Auth auth;
    class TGI tgi;
    class Internal network;

```

### Key Features
- 🔒 Token-based authentication with automatic ban after failed attempts
- 🚦 Rate limiting (global: 10 req/s, per-IP: 10 req/s)
- 🛡️ Security headers and IP protection
- 🔄 Health monitoring and automatic recovery
- 🚀 Optimized for Intel GPUs

## Available Models

### Long Context Models (>8k tokens)
- **Phi-3-mini-128k** - 128k context window
- **Hermes-3-llama3.1** - 8k context window

### Code Generation
- **CodeLlama-7b** - Specialized for code completion
- **Phi-3-mini-4k** - Efficient code generation

### General Purpose
- **Flan-T5-XXL** - Versatile text generation
- **Flan-UL2** - Advanced language understanding
- **Hermes-2-pro** - Balanced performance
- **OpenHermes-Mistral** - Fast inference

Each model includes:
- Individual configuration (`config/model.env`)
- Detailed documentation (`README.md`)
- Optimized parameters for Intel XPU

## Model Management

### Monitoring

```bash
# Check service status
./tgi-status.sh

# View logs
docker logs -f tgi_auth    # Auth service logs
docker logs -f tgi_proxy   # Proxy service logs
docker logs -f <model_container>  # Model logs

# Monitor GPUs
xpu-smi dump -m18         # Detailed memory info
xpu-smi -l               # Live monitoring
xpu-smi discovery       # List available GPUs
```

### Cleanup

```bash
# Clean specific GPU
./service_cleanup.sh --gpu <N>

# Clean all services
./service_cleanup.sh --all
```

## Security & Configuration

### Authentication
```bash
# Generate  token (admin)
python utils/generate_token.py

# Example output:
# --------------------------------------------------------------------------------
# Generated at: 2024-03-22T15:30:45.123456
# Token: XcAwKq7BSbGSoJCsVhUQ2e6MZ4ZOAH_mRR0HgmMNBQg
# --------------------------------------------------------------------------------
```

### Traffic Management
```yaml
# Rate Limits
Global: 10 req/s (burst: 25)
Per-IP: 10 req/s (burst: 25)

# Security Headers
- XSS Protection
- Content Type Nosniff
- Frame Deny
- HSTS
```

## Troubleshooting

### Common Issues
1. GPU not detected
   ```bash
   # Check GPU visibility
   xpu-smi discovery
   # Check GPU devices
   ls -l /dev/dri/
   ```

2. Authentication failures
   ```bash
   # Verify token is set
   echo $VALID_TOKEN
   # Check auth service logs
   docker logs -f tgi_auth
   ```

3. Model startup issues
   ```bash
   # Check model logs
   docker logs -f <model_container>
   # Verify GPU memory
   xpu-smi dump -m18
   ```

### Getting Help
- Check service status: `./tgi-status.sh`
- View detailed logs: `docker logs -f <container>`
- GPU diagnostics: `xpu-smi -l`

## API Usage

### Basic Generation
```bash
# Get endpoint from status
./tgi-status.sh

# Example request (use endpoint from status)
curl -X POST http://localhost:8000/hermes-2-pro-tgi/gpu0/generate \
  -H "Authorization: Bearer $VALID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "inputs": "What is quantum computing?",
    "parameters": {"max_new_tokens": 50}
  }'
```

### Advanced Parameters
```bash
curl -X POST http://localhost:8000/hermes-2-pro-tgi/gpu0/generate \
  -H "Authorization: Bearer $VALID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "inputs": "Explain AI",
    "parameters": {
      "max_new_tokens": 100,
      "temperature": 0.7,
      "top_p": 0.95
    }
  }'
```

### Health Monitoring
```bash
# System health
curl http://localhost:8000/health

# Model status
./tgi-status.sh
```

## GPU Support

### Single GPU Setup
- Automatically detects available GPU
- Uses default GPU 0 if not specified
- Example: `./deploy.sh CodeLlama-7b`

### Multi-GPU Setup
- Specify GPU number during deployment
- Load balance across GPUs
- Example: `./add_model.sh CodeLlama-7b --gpu 1`

## Model Configuration
Each model in the `models/` directory includes:
- Environment configuration (`config/model.env`)
- Model-specific parameters
- GPU memory requirements
- Optimized settings for Intel XPU

Example configuration:
```bash
# models/CodeLlama-7b/config/model.env
MODEL_NAME=codellama-7b-instruct-tgi
MODEL_ID=codellama/CodeLlama-7b-Instruct-hf
TGI_VERSION=2.4.0-intel-xpu
MAX_TOTAL_TOKENS=4096
MAX_INPUT_LENGTH=2048
```

## License Notes

Each model has its own license terms. Please review individual model READMEs before use.

## Accessing the Deployed Service

Once deployed, the service is accessible through the Traefik proxy on port 8000. The endpoint for text generation is:

```http
POST http://localhost:8000/generate
```

All requests must include proper authentication headers as configured in the auth service.

Example curl request:
```bash
curl -X POST http://localhost:8000/generate \
  -H "Authorization: Bearer your-valid-token" \
  -H "Content-Type: application/json" \
  -d '{"inputs": "Your prompt here", "parameters": {}}'
```
## Remote Access

### Option 1: Cloudflare Tunnel (Evaluation)
For quick testing and evaluation, you can use the Cloudflare tunnel:
```bash
# Start tunnel to expose local service
./tunnel.sh

# Optional: Specify custom port
./tunnel.sh --port 8000
```

⚠️ **Important**: This is for evaluation purposes only. For production, use Cloudflare Zero Trust.

### Option 2: SSH Tunnel (Recommended)
For remote access, use SSH tunneling:
```bash
# Forward local port 8000 to remote server
ssh -L 8000:localhost:8000 user@server
```

Benefits:
- 🔒 Secure encrypted connection
- 🚀 Direct connection without third party
- 🛡️ Access control via SSH keys
- 💻 Works with any SSH client

> Note: For production deployments, consider using Cloudflare Zero Trust or your organization's VPN solution.
## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

## Support

For support, please:
1. Check the troubleshooting section
2. Review existing GitHub issues
3. Open a new issue with detailed information about your problem

