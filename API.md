# TGI Service API Documentation

## Authentication
The authentication token is displayed in the console output when the service is first started. You should save this token for future use.

If you need to retrieve the token later, you can get it from the running docker container:
```bash
docker exec tgi_auth env | grep VALID_TOKEN
```

All requests require Bearer token authentication:
```
Authorization: Bearer <your-valid-token>
```

## Base URL Pattern
```
http://localhost:8000/<model-name>/gpu<number>
```

Example:
```
http://localhost:8000/hermes-2-pro-tgi/gpu0
```

## API Endpoints

### 1. Text Generation
Generate text using language models.

**Endpoint**: `POST /<model-name>/gpu<number>/generate`

**Headers**:
- `Content-Type`: `application/json`
- `Authorization`: `Bearer <your-valid-token>`

**Request Schema**:
```json
{
    "inputs": "string",
    "parameters": {
        "max_new_tokens": "integer",
        "temperature": "float",
        "top_p": "float",
        "top_k": "integer",
        "repetition_penalty": "float",
        "stop": ["string"],
        "seed": "integer | null",
        "do_sample": "boolean",
        "best_of": "integer",
        "decoder_input_details": "boolean",
        "details": "boolean",
        "frequency_penalty": "float",
        "typical_p": "float",
        "watermark": "boolean",
        "return_full_text": "boolean"
    },
    "stream": "boolean"
}
```

**Response Schema**:

For non-streaming (`stream: false`):
```json
{
    "generated_text": "string",
    "details": {
        "finish_reason": "string",
        "generated_tokens": "integer",
        "seed": "integer",
        "prefill": [{
            "id": "integer",
            "text": "string",
            "logprob": "float | null"
        }],
        "tokens": [{
            "id": "integer",
            "text": "string",
            "logprob": "float",
            "special": "boolean"
        }]
    }
}
```

For streaming (`stream: true`):
```json
{
    "index": "integer",
    "token": {
        "id": "integer",
        "text": "string",
        "logprob": "float",
        "special": "boolean"
    },
    "generated_text": "string | null",
    "details": "object | null"
}
```

---

## Examples

### Non-Streaming Example
```bash
# Using Hermes-2-pro on GPU 0
curl -X POST http://localhost:8000/hermes-2-pro-tgi/gpu0/generate \
     -H "Authorization: Bearer ${VALID_TOKEN}" \
     -H 'Content-Type: application/json' \
     -d '{
       "inputs": "What are three key benefits of renewable energy?",
       "parameters": {
         "max_new_tokens": 150,
         "temperature": 0.7,
         "do_sample": true,
         "details": true
       },
       "stream": false
     }'
```

Example Response:
```json
{
    "generated_text": "1. Environmental Protection: Renewable energy sources produce little to no greenhouse gas emissions...",
    "details": {
        "finish_reason": "length",
        "generated_tokens": 150,
        "seed": 42
    }
}
```

### Streaming Example
```bash
# Using Hermes-2-pro on GPU 0
curl -X POST http://localhost:8000/hermes-2-pro-tgi/gpu0/generate \
     -H "Authorization: Bearer ${VALID_TOKEN}" \
     -H 'Content-Type: application/json' \
     -d '{
       "inputs": "My name is Olivier and I",
       "parameters": {
         "max_new_tokens": 20,
         "temperature": 0.7,
         "do_sample": true,
         "details": true
       },
       "stream": true
     }'
```

Example Stream Response:
```
data: {"index": 17, "token": {"id": 2955, "text": " design", "logprob": -0.60546875, "special": false}, "generated_text": null, "details": null}
data: {"index": 18, "token": {"id": 11, "text": ",", "logprob": -0.12695312, "special": false}, "generated_text": null, "details": null}
data: {"index": 19, "token": {"id": 5557, "text": " technology", "logprob": 0.0, "special": false}, "generated_text": null, "details": null}
```

---

### 2. **Visual Language Model (VLM)**
Process images and generate text responses.

**Endpoint**: `POST /<model-name>/gpu<number>/generate`

**Headers**:
- `Content-Type`: `application/json`
- `Authorization`: `Bearer <your-valid-token>`

**Request Schema**:
```json
{
    "inputs": "<image>base64_encoded_image</image>\nYour question about the image?",
    "parameters": {
        "max_new_tokens": "integer",
        "temperature": "float",
        "top_p": "float",
        "top_k": "integer",
        "repetition_penalty": "float",
        "do_sample": "boolean",
        "details": "boolean"
    },
    "stream": "boolean"
}
```

### VLM Example
```bash
# Using LLaVA on GPU 0
curl -X POST http://localhost:8000/llava-v1.6-mistral-7b-tgi/gpu0/generate \
     -H "Authorization: Bearer ${VALID_TOKEN}" \
     -H 'Content-Type: application/json' \
     -d '{
       "inputs": "<image>'$(base64 -w0 image.jpg)'</image>\nDescribe this image in detail.",
       "parameters": {
         "max_new_tokens": 200,
         "temperature": 0.3,
         "do_sample": true,
         "details": true
       },
       "stream": false
     }'
```

Example Response:
```json
{
    "generated_text": "The image shows a modern kitchen interior with stainless steel appliances...",
    "details": {
        "finish_reason": "length",
        "generated_tokens": 200,
        "seed": 42
    }
}
```

### Python Example for VLM
```python
import base64
import requests

def encode_image(image_path):
    with open(image_path, "rb") as image_file:
        return base64.b64encode(image_file.read()).decode('utf-8')

# Using LLaVA on GPU 0
url = "http://localhost:8000/llava-v1.6-mistral-7b-tgi/gpu0/generate"
headers = {
    "Content-Type": "application/json",
    "Authorization": f"Bearer {VALID_TOKEN}"
}

# Prepare the request
image_data = encode_image("path/to/image.jpg")
payload = {
    "inputs": f"<image>{image_data}</image>\nDescribe this image in detail.",
    "parameters": {
        "max_new_tokens": 200,
        "temperature": 0.3,
        "do_sample": true,
        "details": true
    },
    "stream": false
}

# Make the request
response = requests.post(url, headers=headers, json=payload)
print(response.json())
```

---

### 3. **Model Information**
Get information about the loaded model.

**Endpoint**: `GET /info`

**Headers**:
- `Authorization`: `Bearer <your-valid-token>`

**Response Schema**:
```json
{
    "model_id": "string",
    "model_dtype": "string",
    "model_device_type": "string",
    "model_pipeline_tag": "string",
    "max_sequence_length": "integer",
    "timestamp": "string",
    "model_sha": "string",
    "sha": "string",
    "docker_label": "string"
}
```

Example Response:
```json
{
    "model_id": "TheBloke/OpenHermes-2.5-Mistral-7B-GGUF",
    "model_dtype": "float16",
    "model_device_type": "cuda",
    "model_pipeline_tag": "text-generation",
    "max_sequence_length": 4096,
    "timestamp": "2024-01-15T12:34:56.789Z",
    "model_sha": "a1b2c3d4e5f6...",
    "sha": "g7h8i9j0k1l2...",
    "docker_label": "tgi-latest"
}
```

---

## Input Formatting

### 1. **Text-Only Input**
Input a text prompt directly into the `inputs` field.

### 2. **Image + Text Input**
Combine an image (base64-encoded) with a question or instruction.
Example:
```json
{
    "inputs": "<image>base64_encoded_image</image>\nWhat is happening in this image?",
    "parameters": {
        "max_new_tokens": 200,
        "temperature": 0.7
    }
}
```

---

## Error Handling

### HTTP Status Codes:
- `200`: Success
- `400`: Bad Request
- `401`: Unauthorized
- `403`: Forbidden (Rate limit reached)
- `429`: Too Many Requests
- `500`: Internal Server Error

**Error Response**:
```json
{
    "error": {
        "message": "string",
        "type": "string",
        "code": "integer"
    }
}
```

---

## Best Practices

### 1. **Resource Management**
- Implement retry logic with exponential backoff.
- Monitor response times.
- Keep requests within model limits.

### 2. **Temperature Settings**
- `0.1-0.3`: Precise, deterministic responses.
- `0.4-0.7`: Balanced creativity.
- `0.8-1.0`: More creative outputs.

### 3. **Performance**
- Optimize input lengths.
- Compress images for VLM requests.
- Use appropriate `max_new_tokens`.

---

## Health Check

**Endpoint**: `GET /health`

**Response**:
```json
{
    "status": "healthy"
}
```

---

## Rate Limits and Performance

### Request Limits
- **Concurrent requests**: Up to 100 per model.
- **Request timeout**: 30 seconds.
- **Maximum input length**: Model-specific (1024-8912 tokens).
- **Maximum output length**: Model-specific.

### Image Requirements
- **Maximum dimensions**: 1024x1024 pixels.
- **Supported formats**: JPEG, PNG, WebP.
- **Recommended size**: < 2MB.
- **Color space**: RGB.
- **Important**: Preprocessing images to smaller dimensions (e.g., 512x512) is strongly recommended to avoid exceeding the model's context length, as larger images consume more tokens and may prevent the model from processing your text prompt effectively.

---

## Security Considerations

### 1. **Token Management**
- Store tokens securely.
- Rotate tokens periodically.
- Never expose tokens in client-side code.

### 2. **Input Validation**
- Sanitize all inputs.
- Validate image sizes and formats.
- Check token lengths for [each model](https://tiberaicommunity.github.io/) sending.



