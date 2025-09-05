#!/bin/bash

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

# Configuration
APP_DIR="/app"
MODELS_DIR="/app/models"
LLAMA_DIR="/app/llama.cpp"
PYTHON_APP="app.py"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
PORT="${PORT:-7860}"
HOST="${HOST:-0.0.0.0}"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check system requirements
check_system_requirements() {
    log_info "🔍 Checking system requirements..."
    
    # Check Python
    if ! command_exists python3; then
        log_error "Python3 is not installed"
        exit 1
    fi
    
    local python_version=$(python3 --version | cut -d' ' -f2)
    log_info "Python version: $python_version"
    
    # Check available memory
    if command_exists free; then
        local memory_mb=$(free -m | awk 'NR==2{printf "%.0f", $2}')
        log_info "Available memory: ${memory_mb}MB"
        
        if [[ $memory_mb -lt 1024 ]]; then
            log_warn "Low memory detected. Model performance may be affected."
        fi
    fi
    
    # Check disk space
    if command_exists df; then
        local disk_space=$(df -h $APP_DIR | awk 'NR==2 {print $4}')
        log_info "Available disk space: $disk_space"
    fi
}

# Function to verify LLaMA installation
verify_llama_installation() {
    log_info "🔍 Verifying LLaMA installation..."
    
    local llama_executables=(
        "/app/llama.cpp/build/bin/llama-cli"
        "/app/llama.cpp/build/bin/main"
        "/app/llama.cpp/llama-cli"
        "/app/llama.cpp/main"
    )
    
    local found_executable=false
    for executable in "${llama_executables[@]}"; do
        if [[ -x "$executable" ]]; then
            log_info "✅ LLaMA executable found: $executable"
            found_executable=true
            break
        fi
    done
    
    if [[ "$found_executable" != "true" ]]; then
        log_error "❌ No LLaMA executable found"
        return 1
    fi
    
    return 0
}

# Function to verify model files
verify_model_files() {
    log_info "🔍 Verifying model files..."
    
    local model_paths=(
        "/app/models/model.gguf"
        "/app/models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
    )
    
    local found_model=false
    for model_path in "${model_paths[@]}"; do
        if [[ -f "$model_path" ]]; then
            local file_size=$(du -h "$model_path" | cut -f1)
            log_info "✅ Model file found: $model_path ($file_size)"
            found_model=true
            break
        fi
    done
    
    if [[ "$found_model" != "true" ]]; then
        log_warn "⚠️ No model files found. Attempting to download..."
        download_model
    fi
    
    return 0
}

# Function to download model if missing
download_model() {
    log_info "📥 Downloading model file..."
    
    mkdir -p "$MODELS_DIR"
    
    local model_url="https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
    local model_path="$MODELS_DIR/model.gguf"
    
    if command_exists wget; then
        log_info "Using wget to download model..."
        if wget -O "$model_path" "$model_url" --progress=dot:giga --timeout=300 --tries=3; then
            log_info "✅ Model downloaded successfully"
        else
            log_warn "⚠️ Model download failed with wget, trying curl..."
            download_with_curl "$model_url" "$model_path"
        fi
    elif command_exists curl; then
        download_with_curl "$model_url" "$model_path"
    else
        log_error "Neither wget nor curl is available for downloading"
        return 1
    fi
}

# Function to download with curl
download_with_curl() {
    local url="$1"
    local output="$2"
    
    log_info "Using curl to download model..."
    if curl -L -o "$output" "$url" --connect-timeout 30 --max-time 1800 --retry 3; then
        log_info "✅ Model downloaded successfully"
    else
        log_error "❌ Model download failed"
        return 1
    fi
}

# Function to check Python dependencies
check_python_dependencies() {
    log_info "🐍 Checking Python dependencies..."
    
    # Try to install from requirements.txt first
    if [[ -f "requirements.txt" ]]; then
        log_info "Installing Python dependencies from requirements.txt..."
        if pip3 install --no-cache-dir --upgrade -r requirements.txt; then
            log_info "✅ Python dependencies from requirements.txt installed successfully"
        else
            log_warn "⚠️ Some dependencies from requirements.txt failed, trying minimal requirements..."
            
            # Fallback to minimal requirements
            if [[ -f "requirements-minimal.txt" ]]; then
                pip3 install --no-cache-dir --upgrade -r requirements-minimal.txt
                log_info "✅ Minimal Python dependencies installed successfully"
            else
                # Install only essential packages
                log_info "Installing essential dependencies manually..."
                pip3 install --no-cache-dir Flask==2.3.3 Werkzeug==2.3.7
            fi
        fi
    else
        log_warn "⚠️ requirements.txt not found, installing essential dependencies..."
        pip3 install --no-cache-dir Flask==2.3.3 Werkzeug==2.3.7
    fi
    
    # Verify critical dependencies
    local critical_deps=("flask" "flask-limiter")
    for dep in "${critical_deps[@]}"; do
        if python3 -c "import $dep" 2>/dev/null; then
            log_debug "✅ $dep is available"
        else
            log_error "❌ Critical dependency $dep is not available"
            return 1
        fi
    done
}

# Function to set up environment
setup_environment() {
    log_info "🔧 Setting up environment..."
    
    # Set environment variables
    export PYTHONUNBUFFERED=1
    export PYTHONPATH="$APP_DIR"
    export PORT="$PORT"
    export HOST="$HOST"
    export LOG_LEVEL="$LOG_LEVEL"
    
    # Create necessary directories
    mkdir -p "$MODELS_DIR"
    mkdir -p "/tmp/llama_cache"
    
    # Set permissions
    chmod -R 755 "$APP_DIR" 2>/dev/null || true
    
    log_info "Environment setup completed"
}

# Function to perform health check
health_check() {
    log_info "🏥 Performing initial health check..."
    
    # Wait a moment for the server to start
    sleep 3
    
    local max_attempts=10
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if command_exists curl; then
            if curl -s -f "http://localhost:$PORT/health" >/dev/null 2>&1; then
                log_info "✅ Health check passed"
                return 0
            fi
        elif command_exists wget; then
            if wget -q --spider "http://localhost:$PORT/health" 2>/dev/null; then
                log_info "✅ Health check passed"
                return 0
            fi
        fi
        
        log_debug "Health check attempt $attempt/$max_attempts failed, retrying..."
        sleep 2
        ((attempt++))
    done
    
    log_warn "⚠️ Health check failed after $max_attempts attempts"
    return 1
}

# Function to start the application
start_application() {
    log_info "🚀 Starting LLaMA API server..."
    log_info "Host: $HOST"
    log_info "Port: $PORT"
    log_info "Log Level: $LOG_LEVEL"
    log_info "Debug: ${DEBUG:-false}"
    
    # Start the application in background for health check
    python3 "$PYTHON_APP" &
    local app_pid=$!
    
    # Perform health check
    if health_check; then
        log_info "🎉 Application started successfully!"
        log_info "API Documentation available at: http://$HOST:$PORT/"
        
        # Kill background process and start normally
        kill $app_pid 2>/dev/null || true
        wait $app_pid 2>/dev/null || true
        
        # Start the application normally
        exec python3 "$PYTHON_APP"
    else
        log_error "❌ Application failed to start properly"
        kill $app_pid 2>/dev/null || true
        exit 1
    fi
}

# Function to clean up on exit
cleanup() {
    log_info "🔄 Cleaning up..."
    # Kill any remaining Python processes
    pkill -f "python3.*app.py" 2>/dev/null || true
}

# Set up trap for cleanup
trap cleanup EXIT INT TERM

# Main execution
main() {
    log_info "🎯 Starting LLaMA API Server Setup"
    log_info "=================================="
    
    # Change to app directory
    cd "$APP_DIR" || {
        log_error "Failed to change to app directory: $APP_DIR"
        exit 1
    }
    
    # Run setup steps
    check_system_requirements
    setup_environment
    verify_llama_installation || {
        log_error "LLaMA installation verification failed"
        exit 1
    }
    verify_model_files
    check_python_dependencies || {
        log_error "Python dependencies check failed"
        exit 1
    }
    
    # Start the application
    start_application
}

# Run main function
main "$@"
