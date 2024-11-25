# FLAN-T5-XXL

Google's FLAN-T5-XXL running on Text Generation Inference (TGI). A powerful model specifically designed for instruction-following tasks with structured outputs.

⚠️ **License Notice**: Before using this model, please review the license terms and usage rights on the [Hugging Face model page](https://huggingface.co/google/flan-t5-xxl).

## Model Information

- **Model**: google/flan-t5-xxl
- **Context Window**: 512 tokens
- **Strengths**: Structured tasks, classification, summarization
- **Optimal Use Cases**: 
  - Text classification
  - Summarization
  - Question answering
  - Translation
  - Structured generation

## Configuration

```env
MODEL_NAME=flan-t5-xxl-tgi
MODEL_ID=google/flan-t5-xxl
TGI_VERSION=2.4.0-intel-xpu
SHM_SIZE=2g
MAX_CONCURRENT_REQUESTS=1
MAX_BATCH_SIZE=1
MAX_TOTAL_TOKENS=512
MAX_INPUT_LENGTH=512
MAX_WAITING_TOKENS=10
```

## Example Usage

### Classification
```bash
curl -X POST http://localhost:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "inputs": "Classify the sentiment of this text: I absolutely loved the movie, it was fantastic!",
    "parameters": {
      "max_new_tokens": 50,
      "temperature": 0.1
    }
  }'
```

### Summarization
```bash
curl -X POST http://localhost:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "inputs": "Summarize this text: Climate change is causing global temperatures to rise. This leads to melting ice caps, rising sea levels, and more extreme weather events. Scientists warn that immediate action is necessary.",
    "parameters": {
      "max_new_tokens": 100,
      "temperature": 0.2
    }
  }'
```

## Best Practices

- Temperature recommendations:
  - 0.1 for classification tasks
  - 0.2-0.3 for summarization
  - 0.1-0.2 for translation
  - 0.2-0.4 for question answering
- Keep inputs concise due to token limit
- Use clear task prefixes:
  - "Classify:"
  - "Summarize:"
  - "Translate:"
  - "Answer:"
- Structure prompts with clear instructions
- Consider token limits when designing prompts 