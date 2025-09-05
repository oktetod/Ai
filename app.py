import os
import subprocess
import logging
import json
import time
from flask import Flask, request, jsonify

# Set up comprehensive logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Initialize the Flask application
app = Flask(__name__)

# Define paths for llama.cpp executable and the model file
POSSIBLE_LLAMA_PATHS = [
    "/app/llama.cpp/llama-cli",
    "/app/llama.cpp/main",
]

POSSIBLE_MODEL_PATHS = [
    "/app/models/model.gguf",
]

# Global variables to store the found paths
LLAMA_CPP_PATH = None
MODEL_PATH = None

def find_executable_paths():
    """Locate the llama.cpp executable and the GGUF model file."""
    global LLAMA_CPP_PATH, MODEL_PATH
    
    logger.info("🔍 Searching for llama.cpp executable...")
    for path in POSSIBLE_LLAMA_PATHS:
        if os.path.exists(path) and os.access(path, os.X_OK):
            LLAMA_CPP_PATH = path
            logger.info(f"✅ Found executable at: {path}")
            break

    logger.info("🔍 Searching for GGUF model file...")
    for path in POSSIBLE_MODEL_PATHS:
        if os.path.exists(path) and os.path.getsize(path) > 1024 * 1024:
            MODEL_PATH = path
            logger.info(f"✅ Found model at: {path}")
            break

def generate_with_llama(prompt, max_tokens=256, temperature=0.8):
    """Generates text using the local llama.cpp subprocess."""
    if not LLAMA_CPP_PATH or not MODEL_PATH:
        return {"error": "Llama.cpp executable or model not found"}, 500

    try:
        command = [
            LLAMA_CPP_PATH,
            "-m", MODEL_PATH,
            "-p", prompt,
            "-n", str(max_tokens),
            "--temp", str(temperature),
            "--no-display-prompt",
            "--log-disable"
        ]
        
        logger.info(f"🚀 Running llama.cpp with prompt: {prompt[:50]}...")
        
        process = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=120,
            check=False
        )

        if process.returncode != 0:
            logger.error(f"⚠️ Process returned non-zero exit code: {process.returncode}")
            logger.error(f"STDERR: {process.stderr}")
            return {"error": "Model execution failed. Check logs for details."}, 500

        output = process.stdout.strip()
        
        if prompt in output:
            output = output.replace(prompt, "", 1).strip()
        
        if not output:
            return {"error": "Model generated an empty response."}, 500
        
        return {"response": output}, 200

    except subprocess.TimeoutExpired:
        logger.error("⏱️ Subprocess timed out.")
        return {"error": "Request timed out. The model may be too slow for the given prompt."}, 500
    except Exception as e:
        logger.error(f"❌ An unexpected error occurred: {e}")
        return {"error": f"An unexpected error occurred: {str(e)}"}, 500

# ---
# Flask API Endpoints
# ---

@app.route("/", methods=["GET"])
def home():
    """Home endpoint for API discovery."""
    return jsonify({
        "status": "🚀 GGUF API is online",
        "endpoints": {
            "/": "This page",
            "/generate": "POST to this endpoint to generate text"
        }
    })

@app.route("/generate", methods=["POST"])
def generate():
    """Endpoint to handle text generation requests."""
    try:
        data = request.json
        prompt = data.get("prompt")
        
        if not prompt:
            return jsonify({"error": "Prompt is missing"}), 400
            
        max_tokens = data.get("max_tokens", 256)
        temperature = data.get("temperature", 0.8)
        
        response, status_code = generate_with_llama(prompt, max_tokens, temperature)
        return jsonify(response), status_code
    except Exception as e:
        logger.error(f"❌ Failed to process request: {e}")
        return jsonify({"error": "Failed to process request"}), 500

@app.route("/health", methods=["GET"])
def health_check():
    """Health check endpoint."""
    healthy = LLAMA_CPP_PATH is not None and MODEL_PATH is not None
    return jsonify({
        "status": "healthy" if healthy else "unhealthy",
        "llama_available": LLAMA_CPP_PATH is not None,
        "model_available": MODEL_PATH is not None,
        "ready": healthy
    }), 200 if healthy else 503

if __name__ == "__main__":
    find_executable_paths()
    port = int(os.environ.get("PORT", 7860))
    logger.info(f"🚀 Starting GGUF API on port {port}")
    app.run(host="0.0.0.0", port=port)
