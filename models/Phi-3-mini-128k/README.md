# Phi-3-mini-128k

Microsoft's Phi-3-mini-128k model running on Text Generation Inference (TGI). A compact model with extended context window (128k), optimized for reasoning, coding, and structured tasks.

⚠️ **License Notice**: Before using this model, please review the license terms and usage rights on the [Hugging Face model page](https://huggingface.co/microsoft/Phi-3-mini-128k).

## Model Information

- **Model**: microsoft/Phi-3-mini-128k
- **Context Window**: 128k tokens
- **Strengths**: Long-context processing, code generation, step-by-step reasoning
- **Optimal Use Cases**: 
  - Processing long documents
  - Multi-file code analysis
  - Extended context reasoning
  - Complex problem solving

## Configuration

```env
MODEL_NAME=phi-3-mini-128k-tgi
MODEL_ID=microsoft/Phi-3-mini-128k
TGI_VERSION=2.4.0-intel-xpu
SHM_SIZE=2g
MAX_CONCURRENT_REQUESTS=1
MAX_BATCH_SIZE=1
MAX_TOTAL_TOKENS=131072
MAX_INPUT_LENGTH=65536
MAX_WAITING_TOKENS=10
```

## Example Usage

### Long Document Analysis
```bash
curl -X POST http://localhost:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "inputs": "Analyze this code base and explain its main components: [long code snippet]",
    "parameters": {
      "max_new_tokens": 500,
      "temperature": 0.2
    }
  }'
```

### Complex Problem Solving
```bash
curl -X POST http://localhost:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "inputs": "Given this long problem description and context, provide a detailed solution: [problem description]",
    "parameters": {
      "max_new_tokens": 1000,
      "temperature": 0.1
    }
  }'
```

## Best Practices

- Use temperature 0.1-0.2 for analytical tasks
- Leverage the large context window for comprehensive analysis
- For long inputs:
  - Structure information clearly
  - Break down complex queries into sections
  - Use descriptive headers and markers 