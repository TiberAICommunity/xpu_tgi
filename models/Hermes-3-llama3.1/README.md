# Hermes-3-llama3.1

NousResearch's Hermes-3 based on Llama3.1 running on Text Generation Inference (TGI). An advanced model offering improved reasoning, coding, and general task performance.

⚠️ **License Notice**: Before using this model, please review the license terms and usage rights on the [Hugging Face model page](https://huggingface.co/NousResearch/Hermes-3-llama3.1).

## Model Information

- **Model**: NousResearch/Hermes-3-llama3.1
- **Context Window**: 8192 tokens
- **Strengths**: Advanced reasoning, coding, analysis
- **Optimal Use Cases**: 
  - Complex problem solving
  - Code generation and analysis
  - Detailed explanations
  - Multi-step reasoning tasks

## Configuration

```env
MODEL_NAME=hermes-3-llama3.1-tgi
MODEL_ID=NousResearch/Hermes-3-llama3.1
TGI_VERSION=2.4.0-intel-xpu
SHM_SIZE=2g
MAX_CONCURRENT_REQUESTS=1
MAX_BATCH_SIZE=1
MAX_TOTAL_TOKENS=8192
MAX_INPUT_LENGTH=4096
MAX_WAITING_TOKENS=10
```

## Example Usage

### Complex Analysis
```bash
curl -X POST http://localhost:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "inputs": "Analyze the implications of quantum computing on current cryptography systems. Provide a structured explanation:",
    "parameters": {
      "max_new_tokens": 500,
      "temperature": 0.3
    }
  }'
```

### Code Generation
```bash
curl -X POST http://localhost:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "inputs": "Create a Python class for managing a library system with methods for adding books, checking out books, and tracking due dates. Include error handling and documentation:",
    "parameters": {
      "max_new_tokens": 800,
      "temperature": 0.2
    }
  }'
```

## Best Practices

- Temperature recommendations:
  - 0.1-0.2 for code generation
  - 0.2-0.3 for analytical tasks
  - 0.3-0.5 for general explanations
- Leverage the larger context window for complex tasks
- Use structured prompts for better organization
- Include specific requirements in prompts
- Break down complex problems into steps 