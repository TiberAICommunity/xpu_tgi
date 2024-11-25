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

# 2. Start a model
./start.sh Flan-T5-XXL

# 3. Make a request
curl -X POST http://localhost:8000/generate \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"inputs": "What is quantum computing?", "parameters": {"max_new_tokens": 50}}'
```

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
