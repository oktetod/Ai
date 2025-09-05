import os
import subprocess
import logging
import json
import time
from typing import Optional, Dict, Any
from dataclasses import dataclass
from flask import Flask, request, jsonify
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from werkzeug.middleware.proxy_fix import ProxyFix
import threading
import queue
import signal
import sys

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize Flask app
app = Flask(__name__)
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)

# Rate limiting
limiter = Limiter(
    app,
    key_func=get_remote_address,
    default_limits=["100 per hour", "20 per minute"]
)

@dataclass
class GenerationRequest:
    prompt: str
    max_tokens: int = 512
    temperature: float = 0.8
    top_p: float = 0.9
    repeat_penalty: float = 1.1

@dataclass
class GenerationResponse:
    success: bool
    text: str
    tokens_generated: int = 0
    generation_time: float = 0.0
    error: Optional[str] = None

class LlamaModelManager:
    """Manages LLaMA model execution and configuration."""
    
    def __init__(self):
        self.llama_path: Optional[str] = None
        self.model_path: Optional[str] = None
        self.is_initialized = False
        self.model_lock = threading.Lock()
        
        # Possible paths for executable and model
        self.possible_llama_paths = [
            "/app/llama.cpp/build/bin/llama-cli",
            "/app/llama.cpp/build/bin/main",
            "/app/llama.cpp/llama-cli",
            "/app/llama.cpp/main",
            "./llama.cpp/build/bin/llama-cli",
            "./llama-cli"
        ]
        
        self.possible_model_paths = [
            "/app/models/model.gguf",
            "/app/models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
            "./models/model.gguf",
            os.environ.get("MODEL_PATH", "")
        ]
        
        # Initialize paths
        self._find_paths()
    
    def _find_paths(self) -> None:
        """Find executable and model paths."""
        logger.info("🔍 Searching for LLaMA executable...")
        
        for path in self.possible_llama_paths:
            if path and os.path.exists(path) and os.access(path, os.X_OK):
                self.llama_path = path
                logger.info(f"✅ LLaMA executable found: {path}")
                break
        else:
            logger.error("❌ LLaMA executable not found")
        
        logger.info("🔍 Searching for model file...")
        
        for path in self.possible_model_paths:
            if path and os.path.exists(path) and os.path.getsize(path) > 1024 * 1024:
                self.model_path = path
                logger.info(f"✅ Model found: {path} ({self._format_size(os.path.getsize(path))})")
                break
        else:
            logger.error("❌ Model file not found")
        
        self.is_initialized = self.llama_path is not None and self.model_path is not None
        
        if self.is_initialized:
            logger.info("🎉 LLaMA model manager initialized successfully")
        else:
            logger.error("⚠️ LLaMA model manager initialization failed")
    
    @staticmethod
    def _format_size(size_bytes: int) -> str:
        """Format file size in human readable format."""
        for unit in ['B', 'KB', 'MB', 'GB']:
            if size_bytes < 1024.0:
                return f"{size_bytes:.1f} {unit}"
            size_bytes /= 1024.0
        return f"{size_bytes:.1f} TB"
    
    def generate(self, request: GenerationRequest) -> GenerationResponse:
        """Generate text using LLaMA model."""
        if not self.is_initialized:
            return GenerationResponse(
                success=False,
                text="",
                error="Model not initialized. Check if LLaMA executable and model file exist."
            )
        
        start_time = time.time()
        
        with self.model_lock:
            try:
                # Validate parameters
                request.max_tokens = max(1, min(request.max_tokens, 4096))
                request.temperature = max(0.1, min(request.temperature, 2.0))
                request.top_p = max(0.1, min(request.top_p, 1.0))
                request.repeat_penalty = max(0.1, min(request.repeat_penalty, 2.0))
                
                # Build command
                command = [
                    self.llama_path,
                    "-m", self.model_path,
                    "-p", request.prompt,
                    "-n", str(request.max_tokens),
                    "--temp", str(request.temperature),
                    "--top-p", str(request.top_p),
                    "--repeat-penalty", str(request.repeat_penalty),
                    "--no-display-prompt",
                    "--log-disable",
                    "--simple-io"
                ]
                
                logger.info(f"🚀 Generating response for prompt: {request.prompt[:100]}...")
                
                # Execute model
                process = subprocess.run(
                    command,
                    capture_output=True,
                    text=True,
                    timeout=180,  # 3 minutes timeout
                    check=False
                )
                
                generation_time = time.time() - start_time
                
                if process.returncode != 0:
                    logger.error(f"⚠️ Process returned non-zero exit code: {process.returncode}")
                    logger.error(f"STDERR: {process.stderr}")
                    return GenerationResponse(
                        success=False,
                        text="",
                        generation_time=generation_time,
                        error=f"Model execution failed with code {process.returncode}"
                    )
                
                output = process.stdout.strip()
                
                # Clean output
                if request.prompt in output:
                    output = output.replace(request.prompt, "", 1).strip()
                
                if not output:
                    return GenerationResponse(
                        success=False,
                        text="",
                        generation_time=generation_time,
                        error="Model generated empty response"
                    )
                
                # Estimate token count (rough approximation)
                tokens_generated = len(output.split())
                
                logger.info(f"✅ Generated {tokens_generated} tokens in {generation_time:.2f}s")
                
                return GenerationResponse(
                    success=True,
                    text=output,
                    tokens_generated=tokens_generated,
                    generation_time=generation_time
                )
                
            except subprocess.TimeoutExpired:
                generation_time = time.time() - start_time
                logger.error("⏱️ Generation timeout exceeded")
                return GenerationResponse(
                    success=False,
                    text="",
                    generation_time=generation_time,
                    error="Generation timeout exceeded (3 minutes)"
                )
            except Exception as e:
                generation_time = time.time() - start_time
                logger.error(f"❌ Unexpected error in generation: {e}")
                return GenerationResponse(
                    success=False,
                    text="",
                    generation_time=generation_time,
                    error=f"Unexpected error: {str(e)}"
                )

# Global model manager
model_manager = LlamaModelManager()

# Error handlers
@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Endpoint not found"}), 404

@app.errorhandler(429)
def rate_limit_exceeded(error):
    return jsonify({
        "error": "Rate limit exceeded",
        "message": "Too many requests. Please try again later."
    }), 429

@app.errorhandler(500)
def internal_error(error):
    return jsonify({"error": "Internal server error"}), 500

# Routes
@app.route("/", methods=["GET"])
def home():
    """API information endpoint."""
    return jsonify({
        "name": "LLaMA Text Generation API",
        "version": "1.0.0",
        "status": "online" if model_manager.is_initialized else "model_not_ready",
        "features": {
            "rate_limiting": "enabled" if (limiter or simple_limiter) else "disabled",
            "rate_limiter_type": "flask-limiter" if limiter else "simple" if simple_limiter else "none"
        },
        "endpoints": {
            "/": "API information",
            "/health": "Health check",
            "/generate": "Text generation (POST)",
            "/model/info": "Model information"
        },
        "rate_limits": {
            "generate_endpoint": "10 requests per minute per IP",
            "global_limits": "100 requests per hour, 20 per minute" if limiter else "10 per minute per IP"
        },
        "documentation": {
            "generate_endpoint": {
                "method": "POST",
                "required_fields": ["prompt"],
                "optional_fields": {
                    "max_tokens": "integer (1-4096, default: 512)",
                    "temperature": "float (0.1-2.0, default: 0.8)",
                    "top_p": "float (0.1-1.0, default: 0.9)",
                    "repeat_penalty": "float (0.1-2.0, default: 1.1)"
                }
            }
        }
    })

@app.route("/health", methods=["GET"])
def health_check():
    """Health check endpoint."""
    healthy = model_manager.is_initialized
    
    health_data = {
        "status": "healthy" if healthy else "unhealthy",
        "timestamp": time.time(),
        "checks": {
            "llama_executable": model_manager.llama_path is not None,
            "model_file": model_manager.model_path is not None,
            "initialization": model_manager.is_initialized
        }
    }
    
    if model_manager.llama_path:
        health_data["llama_path"] = model_manager.llama_path
    
    if model_manager.model_path:
        health_data["model_path"] = model_manager.model_path
        try:
            health_data["model_size"] = model_manager._format_size(os.path.getsize(model_manager.model_path))
        except:
            pass
    
    return jsonify(health_data), 200 if healthy else 503

@app.route("/model/info", methods=["GET"])
def model_info():
    """Get model information."""
    if not model_manager.is_initialized:
        return jsonify({"error": "Model not initialized"}), 503
    
    info = {
        "model_path": model_manager.model_path,
        "executable_path": model_manager.llama_path,
        "model_size": model_manager._format_size(os.path.getsize(model_manager.model_path)),
        "supported_parameters": {
            "max_tokens": "1-4096",
            "temperature": "0.1-2.0",
            "top_p": "0.1-1.0",
            "repeat_penalty": "0.1-2.0"
        }
    }
    
    return jsonify(info)

@app.route("/generate", methods=["POST"])
@limiter.limit("10 per minute")
def generate_text():
    """Generate text using LLaMA model."""
    if not model_manager.is_initialized:
        return jsonify({
            "success": false,
            "error": "Model not initialized. Please check server health."
        }), 503
    
    try:
        data = request.get_json()
        
        if not data or "prompt" not in data:
            return jsonify({
                "success": false,
                "error": "Missing required field: prompt"
            }), 400
        
        # Create generation request
        gen_request = GenerationRequest(
            prompt=str(data["prompt"]).strip(),
            max_tokens=int(data.get("max_tokens", 512)),
            temperature=float(data.get("temperature", 0.8)),
            top_p=float(data.get("top_p", 0.9)),
            repeat_penalty=float(data.get("repeat_penalty", 1.1))
        )
        
        if not gen_request.prompt:
            return jsonify({
                "success": false,
                "error": "Prompt cannot be empty"
            }), 400
        
        # Generate response
        response = model_manager.generate(gen_request)
        
        # Format response
        result = {
            "success": response.success,
            "text": response.text,
            "metadata": {
                "tokens_generated": response.tokens_generated,
                "generation_time": round(response.generation_time, 3),
                "parameters_used": {
                    "max_tokens": gen_request.max_tokens,
                    "temperature": gen_request.temperature,
                    "top_p": gen_request.top_p,
                    "repeat_penalty": gen_request.repeat_penalty
                }
            }
        }
        
        if not response.success:
            result["error"] = response.error
            return jsonify(result), 500
        
        return jsonify(result)
        
    except ValueError as e:
        return jsonify({
            "success": false,
            "error": f"Invalid parameter value: {str(e)}"
        }), 400
    except Exception as e:
        logger.error(f"❌ Error in generate endpoint: {e}")
        return jsonify({
            "success": false,
            "error": "Internal server error"
        }), 500

def signal_handler(sig, frame):
    """Handle shutdown signals gracefully."""
    logger.info("🔄 Received shutdown signal, shutting down gracefully...")
    sys.exit(0)

if __name__ == "__main__":
    # Register signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Get configuration from environment
    port = int(os.environ.get("PORT", 7860))
    debug_mode = os.environ.get("DEBUG", "false").lower() == "true"
    host = os.environ.get("HOST", "0.0.0.0")
    
    logger.info(f"🚀 Starting LLaMA API server on {host}:{port}")
    logger.info(f"📊 Debug mode: {debug_mode}")
    logger.info(f"🤖 Model ready: {model_manager.is_initialized}")
    
    app.run(
        host=host,
        port=port,
        debug=debug_mode,
        threaded=True
    )
