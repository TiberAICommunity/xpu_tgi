# OpenHermes-Mistral

Teknium's OpenHermes-Mistral running on Text Generation Inference (TGI). A Mistral-based model known for its efficient performance and strong reasoning capabilities.

⚠️ **License Notice**: Before using this model, please review the license terms and usage rights on the [Hugging Face model page](https://huggingface.co/teknium/OpenHermes-Mistral).

## Model Information

- **Model**: teknium/OpenHermes-Mistral
- **Context Window**: 8192 tokens
- **Strengths**: Efficient reasoning, balanced responses, instruction following
- **Optimal Use Cases**: 
  - Technical explanations
  - Logical reasoning
  - Code assistance
  - General knowledge tasks

## Configuration

```env
MODEL_NAME=openhermes-mistral-tgi
MODEL_ID=teknium/OpenHermes-Mistral
TGI_VERSION=2.4.0-intel-xpu
SHM_SIZE=2g
MAX_CONCURRENT_REQUESTS=1
MAX_BATCH_SIZE=1
MAX_TOTAL_TOKENS=8192
MAX_INPUT_LENGTH=4096
MAX_WAITING_TOKENS=10
```

## Example Usage

### Technical Explanation
```bash
curl -X POST http://localhost:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "inputs": "Explain how HTTPS encryption works in a client-server architecture. Include key concepts and steps:",
    "parameters": {
      "max_new_tokens": 400,
      "temperature": 0.3
    }
  }'
```

### Problem Solving
```bash
curl -X POST http://localhost:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "inputs": "Design a system for managing concurrent user sessions in a web application. Consider scalability and security aspects:",
    "parameters": {
      "max_new_tokens": 500,
      "temperature": 0.2
    }
  }'
```

## Best Practices

- Temperature settings:
  - 0.1-0.2 for technical/precise responses
  - 0.2-0.4 for balanced explanations
  - 0.4-0.7 for more creative tasks
- Provide clear context in prompts
- Use structured input for complex queries
- Specify desired format when needed
- Leverage model's strength in technical reasoning 