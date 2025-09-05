#!/bin/bash

# ==========================================================
# Script ini akan dijalankan sebagai entrypoint container
# untuk memastikan semua komponen siap sebelum memulai API.
# ==========================================================

echo "🚀 Starting API setup..."
echo "=============================="

# Check if the llama.cpp executable exists
if [ -f "/app/llama.cpp/main" ]; then
    echo "✅ Llama.cpp executable found."
else
    echo "❌ Llama.cpp executable not found. Exiting."
    exit 1
fi

# Check if the GGUF model file exists and is not empty
if [ -s "/app/models/model.gguf" ]; then
    echo "✅ GGUF model file found."
else
    echo "❌ GGUF model file not found or is empty. Exiting."
    exit 1
fi

echo "✅ All required files found. Starting the API..."
echo "=============================="

# Start the Flask API server
# The python command runs the app.py file
exec python3 /app/app.py
