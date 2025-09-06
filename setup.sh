#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -e

echo "Running initial setup..."

# Check if model exists, otherwise download.
if [ ! -f "models/model.gguf" ]; then
    echo "Model not found, downloading..."
    wget -O models/model.gguf "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf" || \
    wget -O models/model.gguf "https://huggingface.co/microsoft/DialoGPT-small/resolve/main/pytorch_model.bin" || \
    echo "Model download failed - will use local model if available"
else
    echo "Model already exists. Skipping download."
fi

echo "Setup complete. Starting applications..."

# The rest of the application startup will be handled by the run.sh script.
