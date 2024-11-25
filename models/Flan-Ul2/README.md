# Flan-UL2 Text Generation Service

This service runs Google's Flan-UL2 model using Text Generation Inference (TGI) on Intel XPU. Flan-UL2 excels at instruction-following tasks like translation, summarization, and question answering.

## License & Usage Rights

⚠️ **Important**: Before deploying this model, please:
1. Review the license at [google/flan-ul2](https://huggingface.co/google/flan-ul2)
2. Ensure your use case complies with the model's terms of use
3. Check for any commercial usage restrictions
4. Verify any attribution requirements

## Quick Start

```bash
# Start the service
./start.sh

# Check status
./status.sh

# Stop the service
./stop.sh
```

## Model Information

- **Model**: google/flan-ul2
- **Type**: Text Generation / Instruction Following
- **Framework**: Text Generation Inference (TGI)
- **Port**: 8083
- **Use Cases**: Translation, Summarization, Question Answering, Classification

## Configuration

Key settings in `config/model.env`:
```env
MODEL_NAME=flan-ul2-tgi
MODEL_ID=google/flan-ul2
TGI_VERSION=2.4.0-intel-xpu
SHM_SIZE=8g
MAX_CONCURRENT_REQUESTS=10
MAX_BATCH_SIZE=1
MAX_TOTAL_TOKENS=4096
MAX_INPUT_LENGTH=2039
MAX_WAITING_TOKENS=20
```

## Example Usage

Flan-UL2 is designed for instruction-following tasks. Here are some examples:

### 1. Translation
```bash
curl -X POST http://localhost:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "inputs": "Translate English to French: The weather is beautiful today.",
    "parameters": {
      "max_new_tokens": 50,
      "temperature": 0.3
    }
  }'
```

### 2. Text Summarization
```bash
curl -X POST http://localhost:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "inputs": "Summarize this text: The James Webb Space Telescope (JWST) is the largest optical telescope in space. It was launched in December 2021 and is designed to conduct infrared astronomy. Its capabilities allow it to see objects too early, distant, or faint for the Hubble Space Telescope.",
    "parameters": {
      "max_new_tokens": 100,
      "temperature": 0.3
    }
  }'
```

### 3. Question Answering
```bash
curl -X POST http://localhost:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "inputs": "Answer this question: What causes the seasons on Earth? Provide a detailed explanation.",
    "parameters": {
      "max_new_tokens": 150,
      "temperature": 0.3
    }
  }'
```

### Health Check
```bash
curl http://localhost:8000/v1/models
```

## Best Practices

1. **Task Formatting**:
   - Always start with clear instructions
   - Be specific about the task requirements
   - Use appropriate prefixes like "Translate:", "Summarize:", "Answer:"

2. **Parameter Settings**:
   - Use lower temperature (0.1-0.3) for factual tasks
   - Increase temperature (0.6-0.8) for creative tasks
   - Adjust max_new_tokens based on expected response length

## Notes

- The service is configured for optimal performance on Intel XPU
- Batch size and concurrent requests are optimized for stability
- Model is automatically downloaded on first run
- Flan-UL2 is best suited for instruction-following tasks, not open-ended chat
- The model performs well on structured tasks with clear instructions
