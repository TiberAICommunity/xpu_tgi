# Phi-3-mini-4k

Microsoft's Phi-3-mini-4k model running on Text Generation Inference (TGI). A compact yet powerful model optimized for reasoning, coding, and structured tasks.

⚠️ **License Notice**: Before using this model, please review the license terms and usage rights on the [Hugging Face model page](https://huggingface.co/microsoft/Phi-3-mini-4k-instruct).

## Model Information

- **Model**: microsoft/Phi-3-mini-4k-instruct
- **Context Window**: 4096 tokens
- **Strengths**: Code generation, step-by-step reasoning, math problems
- **Optimal Use Cases**: 
  - Writing and debugging code
  - Solving mathematical problems
  - Explaining technical concepts
  - Logical reasoning tasks

## Configuration

```env
MODEL_NAME=phi-3-mini-4k-tgi
MODEL_ID=microsoft/Phi-3-mini-4k-instruct
TGI_VERSION=2.4.0-intel-xpu
SHM_SIZE=2g
MAX_CONCURRENT_REQUESTS=1
MAX_BATCH_SIZE=1
MAX_TOTAL_TOKENS=4096
MAX_INPUT_LENGTH=2048
MAX_WAITING_TOKENS=10
```

## Example Usage

### Code Generation
```bash
curl -X POST http://localhost:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "inputs": "Write a Python function that calculates the factorial of a number. Include comments explaining the logic:",
    "parameters": {
      "max_new_tokens": 150,
      "temperature": 0.2
    }
  }'
```

### Step-by-Step Math
```bash
curl -X POST http://localhost:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "inputs": "Solve step by step: A store offers a 15% discount on a $80 item. What is the final price after tax if the tax rate is 8%?",
    "parameters": {
      "max_new_tokens": 200,
      "temperature": 0.1
    }
  }'
```

## Best Practices

- Use temperature 0.1-0.2 for code and math
- Include "step by step" for complex problems
- For coding tasks, specify:
  - Programming language
  - Desired functionality
  - Any specific requirements (comments, error handling, etc.)
- Break down complex queries into smaller, logical steps
