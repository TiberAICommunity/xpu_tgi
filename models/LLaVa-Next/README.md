# LLaVa-Next

The LLaVA-NeXT model was proposed in LLaVA-NeXT: Improved reasoning, OCR, and world knowledge by Haotian Liu, Chunyuan Li, Yuheng Li, Bo Li, Yuanhan Zhang, Sheng Shen, Yong Jae Lee. This version uses the Mistral-7B base model, offering an excellent balance of performance and efficiency.

⚠️ **License Notice**: Before using this model, please review the license terms and usage rights on the Hugging Face model page.

## Model Information

- **Model**: llava-hf/llava-v1.6-mistral-7b-hf
- **Base Model**: Mistral-7B
- **Context Window**: 4096 tokens
- **Parameters**: 7B
- **Strengths**: 
  - Efficient multimodal processing
  - Strong OCR capabilities
  - Improved visual reasoning
  - Lower memory requirements than 13B variant

## Key Features
- Built on the efficient Mistral-7B architecture
- Enhanced visual understanding capabilities
- Better performance on OCR tasks
- Improved reasoning about spatial relationships
- More efficient resource utilization

## Resource Requirements
- Minimum GPU Memory: 8GB
- Recommended GPU Memory: 12GB
- CPU RAM: 16GB recommended

## Configuration

```env
MODEL_NAME=llava-v1.6-mistral-7b-hf-tgi
MODEL_ID=llava-hf/llava-v1.6-mistral-7b-hf
TGI_VERSION=latest-intel-xpu
SHM_SIZE=8g
MAX_CONCURRENT_REQUESTS=128
MAX_BATCH_SIZE=4
MAX_TOTAL_TOKENS=4096
MAX_INPUT_LENGTH=2048
MAX_WAITING_TOKENS=10
```

## Example Usage

### Basic Image Analysis
```python
from huggingface_hub import InferenceClient
import base64

def encode_image(image_path):
    with open(image_path, "rb") as image_file:
        return base64.b64encode(image_file.read()).decode('utf-8')

client = InferenceClient("http://localhost:8000")
image_data = encode_image("path/to/image.jpg")
prompt = f"<image>{image_data}</image>\nDescribe what you see in this image in detail."

response = client.text_generation(
    prompt,
    max_new_tokens=200,
    temperature=0.2
)
```

### OCR Example
```python
# Example for text extraction from images
prompt = f"<image>{image_data}</image>\nExtract and list all text visible in this image."

response = client.text_generation(
    prompt,
    max_new_tokens=150,
    temperature=0.1
)
```

### Visual Question Answering
```python
prompt = f"""<image>{image_data}</image>
Answer the following questions about the image:
1. What are the main objects present?
2. What colors are dominant?
3. Is there any text visible?
4. Describe the spatial layout."""

response = client.text_generation(
    prompt,
    max_new_tokens=300,
    temperature=0.2
)
```

## Best Practices

### Image Processing
- Ensure images are clear and well-lit
- Keep images under 1024x1024 pixels
- Use high-quality images for OCR tasks
- Consider image compression for large files

### Prompting Strategies
- Be specific about what aspects of the image to analyze
- For OCR tasks:
  - Request specific formatting of extracted text
  - Specify if order/layout matters
- For visual analysis:
  - Break down complex queries into specific questions
  - Include spatial relationship questions when relevant

### Temperature Settings
- 0.1: OCR and text extraction
- 0.2: Detailed image analysis and object detection
- 0.3-0.4: General image description
- 0.5-0.7: Creative image interpretation

## Image Requirements

- Maximum image dimensions: 1024x1024 pixels
- Images larger than 1024x1024 will be automatically resized
- Supported formats: JPEG, PNG, WebP
- Images are processed using CLIP's image processor
