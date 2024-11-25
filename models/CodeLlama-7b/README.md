# CodeLlama-7b-instruct

Meta's CodeLlama 7B Instruct model running on Text Generation Inference (TGI). Specialized for code generation and understanding across multiple programming languages.

⚠️ **License Notice**: This model is available under the Llama 2 Community License. Before using this model:
1. Review the complete license at [CodeLlama-7b-instruct](https://huggingface.co/codellama/CodeLlama-7b-instruct)
2. Accept Meta's Llama 2 License
3. Ensure compliance with usage terms and conditions
4. Check commercial usage requirements

## Model Information

- **Model**: codellama/CodeLlama-7b-instruct
- **Context Window**: 4096 tokens
- **Strengths**: Code generation, understanding, and modification
- **Optimal Use Cases**: 
  - Code completion
  - Bug fixing
  - Code explanation
  - Documentation generation
  - Code review suggestions

## Configuration

```env
MODEL_NAME=codellama-7b-instruct-tgi
MODEL_ID=codellama/CodeLlama-7b-instruct
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
    "inputs": "Write a Python function that implements a binary search tree with insert and search methods. Include docstrings and type hints:",
    "parameters": {
      "max_new_tokens": 500,
      "temperature": 0.1
    }
  }'
```

### Code Explanation
```bash
curl -X POST http://localhost:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "inputs": "Explain this code line by line:\n\ndef quicksort(arr):\n    if len(arr) <= 1:\n        return arr\n    pivot = arr[len(arr) // 2]\n    left = [x for x in arr if x < pivot]\n    middle = [x for x in arr if x == pivot]\n    right = [x for x in arr if x > pivot]\n    return quicksort(left) + middle + quicksort(right)",
    "parameters": {
      "max_new_tokens": 400,
      "temperature": 0.2
    }
  }'
```

## Best Practices

- Temperature settings:
  - 0.1 for exact code generation
  - 0.2 for code explanations
  - 0.3-0.4 for creative solutions
- Include in prompts:
  - Target programming language
  - Desired functionality
  - Required patterns or conventions
  - Performance considerations
  - Error handling requirements
- Use clear code-specific instructions:
  - "Write a function that..."
  - "Debug this code..."
  - "Explain this implementation..."
  - "Optimize this function..." 