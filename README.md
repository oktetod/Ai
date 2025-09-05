---
license: apache-2.0
title: Tes1
sdk: docker
emoji: 💻
colorFrom: blue
colorTo: green
pinned: true
---
# GGUF Model API on Hugging Face Spaces

This is a Flask API for running GGUF (GPT-Generated Unified Format) models using llama.cpp on Hugging Face Spaces.

## Features

- 🤖 **Local GGUF Model Inference**: Run quantized models efficiently
- 🚀 **REST API**: Easy-to-use HTTP endpoints for text generation
- 📊 **Web Interface**: Built-in testing interface
- 📝 **Telegram Integration**: Webhook support for Telegram bots (logging only)
- 🔧 **Debug Tools**: Comprehensive debugging and monitoring

## API Endpoints

### `GET /`
Get system status and available endpoints

### `POST /generate`
Generate text with your model
```json
{
  "prompt": "Your prompt here",
  "max_tokens": 256,
  "temperature": 0.7
}
```

### `GET /debug`
Get detailed system information and troubleshooting data

### `GET /test_generate`
Quick test with a predefined prompt

## Configuration

The application automatically searches for:
- **llama.cpp executable**: `llama-cli`, `main` in various locations
- **GGUF model files**: `.gguf` files in `/app/models/` and other directories

## Model Setup

1. Place your GGUF model file in `/app/models/model.gguf`
2. Or update the `POSSIBLE_MODEL_PATHS` in `app.py` to point to your model location

## Usage Examples

### Python
```python
import requests

response = requests.post('YOUR_SPACE_URL/generate', json={
    'prompt': 'Hello, how are you?',
    'max_tokens': 100,
    'temperature': 0.7
})

result = response.json()
print(result['generated_text'])
```

### JavaScript
```javascript
fetch('YOUR_SPACE_URL/generate', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({
        prompt: 'Hello, how are you?',
        max_tokens: 100,
        temperature: 0.7
    })
})
.then(r => r.json())
.then(data => console.log(data.generated_text));
```

## Troubleshooting

1. **Model not found**: Check the `/debug` endpoint for available files
2. **llama.cpp not found**: Ensure the build process completed successfully
3. **Generation fails**: Check model compatibility and available memory

Visit the web interface at your Space URL for interactive testing and debugging tools.

---

**Note**: This Space runs models locally without external API calls. All inference is performed on Hugging Face's infrastructure.