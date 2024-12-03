# Hermes-2-pro

NousResearch's Hermes-2-pro running on Text Generation Inference (TGI). A powerful model based on Llama-3-8B fine-tuned for instruction following, reasoning, and general knowledge tasks.

⚠️ **License Notice**: Before using this model, please review the license terms and usage rights on the [Hugging Face model page](https://huggingface.co/NousResearch/Hermes-2-Pro-Llama-3-8B).

## Model Information

- **Model**: NousResearch/Hermes-2-Pro-Llama-3-8B
- **Context Window**: 4096 tokens
- **Strengths**: Instruction following, reasoning, creative writing
- **Optimal Use Cases**: 
  - Complex reasoning tasks
  - Creative writing
  - General knowledge Q&A
  - Task decomposition

## Configuration

```env
MODEL_NAME=hermes-2-pro-tgi
MODEL_ID=NousResearch/Hermes-2-Pro-Llama-3-8B
TGI_VERSION=2.4.0-intel-xpu
SHM_SIZE=2g
MAX_CONCURRENT_REQUESTS=1
MAX_BATCH_SIZE=1
MAX_TOTAL_TOKENS=4096
MAX_INPUT_LENGTH=2048
MAX_WAITING_TOKENS=10
```

## Example Usage

### Complex Reasoning
```bash
curl -X POST http://localhost:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "inputs": "Explain the concept of quantum entanglement to a high school student. Break it down into simple terms:",
    "parameters": {
      "max_new_tokens": 250,
      "temperature": 0.3
    }
  }'
```

### Creative Writing
```bash
curl -X POST http://localhost:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "inputs": "Write a short story about a time traveler who meets their younger self. Focus on the emotional impact:",
    "parameters": {
      "max_new_tokens": 300,
      "temperature": 0.7
    }
  }'
```

## Best Practices

- Adjust temperature based on task:
  - 0.1-0.3 for factual/analytical responses
  - 0.5-0.7 for creative writing
  - 0.3-0.5 for balanced responses
- Use clear, specific instructions
- For complex queries, break down into steps
- Include context when needed for better responses 