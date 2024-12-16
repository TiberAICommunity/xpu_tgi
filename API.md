# TGI Service API Documentation

## Base URL
`http://localhost:8000/generate`

## Authentication
All requests require Bearer token authentication:
```
Authorization: Bearer <your-valid-token>
```

### Rate Limiting for Failed Authentication
- **Maximum failed attempts**: 5
- **Ban duration**: 300 seconds
- **Reset time**: 1800 seconds

---

## API Endpoints

### 1. **Text Generation (LLM)**
Generate text using language models.

**Endpoint**: `POST /generate`

**Headers**:
- `Content-Type`: `application/json`
- `Authorization`: `Bearer <your-valid-token>`

**Request Body**:
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
        "seed": "integer",                
        "do_sample": "boolean"           
    }
}
```

**Response**:
```json
{
    "generated_text": "string",
    "details": {
        "finish_reason": "string",
        "generated_tokens": "integer",
        "seed": "integer"
    }
}
```

---

### 2. **Visual Language Model (VLM)**
Process images and generate text responses.

**Endpoint**: `POST /generate`

**Headers**:
- `Content-Type`: `application/json`
- `Authorization`: `Bearer <your-valid-token>`

**Request Format**:
```json
{
    "inputs": "<image>base64_encoded_image</image>\nYour question about the image?",
    "parameters": {
        "max_new_tokens": "integer",
        "temperature": "float"
    }
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

## Examples

### Text Generation Example (LLM)
```python
import requests

headers = {
    "Content-Type": "application/json",
    "Authorization": "Bearer <your-valid-token>"
}
payload = {
    "inputs": "<|im_start|>system\nYou are a helpful assistant.\n<|im_end|>\n<|im_start|>user\nWhat are three key benefits of renewable energy?\n<|im_end|>\n<|im_start|>assistant",
    "parameters": {
        "max_new_tokens": 150,
        "temperature": 0.7
    }
}
response = requests.post("http://localhost:8000/generate", headers=headers, json=payload)
print(response.json())
```

### Image Analysis Example (VLM)
```python
import base64
from PIL import Image
import requests
from io import BytesIO

# Load and prepare image
image = Image.open("example.jpg")
# Resize if needed (max 1024x1024)
buffer = BytesIO()
image.save(buffer, format="JPEG")
base64_image = base64.b64encode(buffer.getvalue()).decode('utf-8')

# Prepare request
payload = {
    "inputs": f"<|im_start|>system\nAnalyze the image.\n<|im_end|>\n<|im_start|>user\n<image>{base64_image}</image>\nDescribe what you see in detail.\n<|im_end|>\n<|im_start|>assistant",
    "parameters": {
        "max_new_tokens": 200,
        "temperature": 0.3
    }
}
response = requests.post("http://localhost:8000/generate", headers=headers, json=payload)
print(response.json())
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



