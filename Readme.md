# TGI Models Collection

Welcome to `xpu_tgi`! 🚀  

A curated collection of Text Generation Inference (TGI) models optimized for Intel XPU, with built-in security and traffic management.

<div align="center">
<img src="./hi_tgi.jpg" alt="TGI LLM Servers" width="400"/>
</div>

## Quick Start

```bash
# 1. Generate authentication token
python utils/generate_token.py

# Example output:
# --------------------------------------------------------------------------------
# Generated at: 2024-03-22T15:30:45.123456
# Token: XcAwKq7BSbGSoJCsVhUQ2e6MZ4ZOAH_mRR0HgmMNBQg
# --------------------------------------------------------------------------------

# 2. Set the token as environment variable
export VALID_TOKEN=XcAwKq7BSbGSoJCsVhUQ2e6MZ4ZOAH_mRR0HgmMNBQg

# 3. Start a model (with optional caching)
./start.sh --cache-models Flan-T5-XXL  # Enable caching for faster reloads
# or
./start.sh Flan-T5-XXL                 # Without caching

# 4. Stop a model or all models
./stop.sh Flan-T5-XXL                  # Stop a specific model
# or
./stop.sh                              # Stop all models

# 5. Clean up a model or all models
./cleanup.sh Flan-T5-XXL               # Clean up a specific model
# or
./cleanup.sh                           # Clean up all models

# 6. Make a request (use the same token)
curl -X POST http://localhost:8000/generate \
  -H "Authorization: Bearer $VALID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"inputs": "What is quantum computing?", "parameters": {"max_new_tokens": 50}}'
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

## Security & Configuration

### Authentication
```bash
# Generate secure token (admin)
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

## API Usage

### Basic Generation
```bash
curl -X POST http://localhost:8000/generate \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "inputs": "What is quantum computing?",
    "parameters": {"max_new_tokens": 50}
  }'
```

### Advanced Parameters
```bash
curl -X POST http://localhost:8000/generate \
  -H "Authorization: Bearer YOUR_TOKEN" \
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
curl http://localhost:8000/v1/models
```

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) first.

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

## Model Management

### Stopping Models
You can stop a specific model or all models:

```bash
# Stop a specific model
./stop.sh your-model-name

# Stop all models
./stop.sh
```

### Cleaning Up Models
You can clean up resources for a specific model or all models:

```bash
# Clean up a specific model
./cleanup.sh your-model-name

# Clean up all models
./cleanup.sh
```

These updates to the `Readme.md` provide clear instructions on how to use the new options for stopping and cleaning up models, ensuring users can easily manage their models with the updated scripts.
