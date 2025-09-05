#!/bin/bash

set -e  # Keluar pada setiap kesalahan

# Kode warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # Tanpa Warna

# Fungsi logging
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

# Konfigurasi
APP_DIR="/app"
MODELS_DIR="/app/models"
LLAMA_DIR="/app/llama.cpp"
PYTHON_APP="app.py"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
PORT="${PORT:-7860}"
HOST="${HOST:-0.0.0.0}"

# Fungsi untuk memeriksa apakah perintah ada
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Fungsi untuk memeriksa persyaratan sistem
check_system_requirements() {
    log_info "🔍 Memeriksa persyaratan sistem..."
    
    # Periksa Python
    if ! command_exists python3; then
        log_error "Python3 tidak terinstal"
        exit 1
    fi
    
    local python_version=$(python3 --version | cut -d' ' -f2)
    log_info "Versi Python: $python_version"
    
    # Periksa memori yang tersedia
    if command_exists free; then
        local memory_mb=$(free -m | awk 'NR==2{printf "%.0f", $2}')
        log_info "Memori yang tersedia: ${memory_mb}MB"
        
        if [[ $memory_mb -lt 1024 ]]; then
            log_warn "Memori rendah terdeteksi. Performa model mungkin terpengaruh."
        fi
    fi
    
    # Periksa ruang disk
    if command_exists df; then
        local disk_space=$(df -h $APP_DIR | awk 'NR==2 {print $4}')
        log_info "Ruang disk yang tersedia: $disk_space"
    fi
}

# Fungsi untuk memverifikasi instalasi LLaMA
verify_llama_installation() {
    log_info "🔍 Memverifikasi instalasi LLaMA..."
    
    local llama_executables=(
        "/app/llama.cpp/build/bin/llama-cli"
        "/app/llama.cpp/build/bin/main"
        "/app/llama.cpp/llama-cli"
        "/app/llama.cpp/main"
    )
    
    local found_executable=false
    for executable in "${llama_executables[@]}"; do
        if [[ -x "$executable" ]]; then
            log_info "✅ Executable LLaMA ditemukan: $executable"
            found_executable=true
            break
        fi
    done
    
    if [[ "$found_executable" != "true" ]]; then
        log_error "❌ Tidak ada executable LLaMA yang ditemukan"
        return 1
    fi
    
    return 0
}

# Fungsi untuk memverifikasi file model
verify_model_files() {
    log_info "🔍 Memverifikasi file model..."
    
    local model_paths=(
        "/app/models/model.gguf"
        "/app/models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
    )
    
    local found_model=false
    for model_path in "${model_paths[@]}"; do
        if [[ -f "$model_path" ]]; then
            local file_size=$(du -h "$model_path" | cut -f1)
            log_info "✅ File model ditemukan: $model_path ($file_size)"
            found_model=true
            break
        fi
    done
    
    if [[ "$found_model" != "true" ]]; then
        log_warn "⚠️ Tidak ada file model yang ditemukan. Mencoba mengunduh..."
        download_model
    fi
    
    return 0
}

# Fungsi untuk mengunduh model jika hilang
download_model() {
    log_info "📥 Mengunduh file model..."
    
    mkdir -p "$MODELS_DIR"
    
    local model_url="https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
    local model_path="$MODELS_DIR/model.gguf"
    
    if command_exists wget; then
        log_info "Menggunakan wget untuk mengunduh model..."
        if wget -O "$model_path" "$model_url" --progress=dot:giga --timeout=300 --tries=3; then
            log_info "✅ Model berhasil diunduh"
        else
            log_warn "⚠️ Unduhan model gagal dengan wget, mencoba curl..."
            download_with_curl "$model_url" "$model_path"
        fi
    elif command_exists curl; then
        download_with_curl "$model_url" "$model_path"
    else
        log_error "Baik wget maupun curl tidak tersedia untuk mengunduh"
        return 1
    fi
}

# Fungsi untuk mengunduh dengan curl
download_with_curl() {
    local url="$1"
    local output="$2"
    
    log_info "Menggunakan curl untuk mengunduh model..."
    if curl -L -o "$output" "$url" --connect-timeout 30 --max-time 1800 --retry 3; then
        log_info "✅ Model berhasil diunduh"
    else
        log_error "❌ Unduhan model gagal"
        return 1
    fi
}

# Fungsi untuk memeriksa dependensi Python
check_python_dependencies() {
    log_info "🐍 Memeriksa dependensi Python..."
    
    # Coba instal dari requirements.txt terlebih dahulu
    if [[ -f "requirements.txt" ]]; then
        log_info "Menginstal dependensi Python dari requirements.txt..."
        if pip3 install --no-cache-dir --upgrade -r requirements.txt; then
            log_info "✅ Dependensi Python dari requirements.txt berhasil diinstal"
        else
            log_warn "⚠️ Beberapa dependensi dari requirements.txt gagal, mencoba persyaratan minimal..."
            
            # Fallback ke persyaratan minimal yang diperbarui
            if [[ -f "requirements-minimal.txt" ]]; then
                pip3 install --no-cache-dir --upgrade -r requirements-minimal.txt
                log_info "✅ Dependensi Python minimal berhasil diinstal"
            else
                # Menginstal paket esensial secara manual, termasuk flask-limiter
                log_info "Menginstal dependensi esensial secara manual..."
                pip3 install --no-cache-dir Flask==2.3.3 Werkzeug==2.3.7 flask-limiter
            fi
        fi
    else
        log_warn "⚠️ requirements.txt tidak ditemukan, menginstal dependensi esensial..."
        # Menginstal paket esensial secara manual, termasuk flask-limiter
        pip3 install --no-cache-dir Flask==2.3.3 Werkzeug==2.3.7 flask-limiter
    fi
    
    # Verifikasi dependensi kritis
    local critical_deps=("flask" "flask-limiter")
    for dep in "${critical_deps[@]}"; do
        if python3 -c "import $dep" 2>/dev/null; then
            log_debug "✅ $dep tersedia"
        else
            log_error "❌ Dependensi kritis $dep tidak tersedia"
            return 1
        fi
    done
}

# Fungsi untuk menyiapkan lingkungan
setup_environment() {
    log_info "🔧 Menyiapkan lingkungan..."
    
    # Set variabel lingkungan
    export PYTHONUNBUFFERED=1
    export PYTHONPATH="$APP_DIR"
    export PORT="$PORT"
    export HOST="$HOST"
    export LOG_LEVEL="$LOG_LEVEL"
    
    # Buat direktori yang diperlukan
    mkdir -p "$MODELS_DIR"
    mkdir -p "/tmp/llama_cache"
    
    # Set izin
    chmod -R 755 "$APP_DIR" 2>/dev/null || true
    
    log_info "Penyiapan lingkungan selesai"
}

# Fungsi untuk melakukan pemeriksaan kesehatan
health_check() {
    log_info "🏥 Melakukan pemeriksaan kesehatan awal..."
    
    # Tunggu sebentar agar server mulai
    sleep 3
    
    local max_attempts=10
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if command_exists curl; then
            if curl -s -f "http://localhost:$PORT/health" >/dev/null 2>&1; then
                log_info "✅ Pemeriksaan kesehatan berhasil"
                return 0
            fi
        elif command_exists wget; then
            if wget -q --spider "http://localhost:$PORT/health" 2>/dev/null; then
                log_info "✅ Pemeriksaan kesehatan berhasil"
                return 0
            fi
        fi
        
        log_debug "Percobaan pemeriksaan kesehatan $attempt/$max_attempts gagal, mencoba lagi..."
        sleep 2
        ((attempt++))
    done
    
    log_warn "⚠️ Pemeriksaan kesehatan gagal setelah $max_attempts percobaan"
    return 1
}

# Fungsi untuk memulai aplikasi
start_application() {
    log_info "🚀 Memulai server API LLaMA..."
    log_info "Host: $HOST"
    log_info "Port: $PORT"
    log_info "Tingkat Log: $LOG_LEVEL"
    log_info "Debug: ${DEBUG:-false}"
    
    # Mulai aplikasi di latar belakang untuk pemeriksaan kesehatan
    python3 "$PYTHON_APP" &
    local app_pid=$!
    
    # Lakukan pemeriksaan kesehatan
    if health_check; then
        log_info "🎉 Aplikasi berhasil dimulai!"
        log_info "Dokumentasi API tersedia di: http://$HOST:$PORT/"
        
        # Matikan proses latar belakang dan mulai secara normal
        kill $app_pid 2>/dev/null || true
        wait $app_pid 2>/dev/null || true
        
        # Mulai aplikasi secara normal
        exec python3 "$PYTHON_APP"
    else
        log_error "❌ Aplikasi gagal dimulai dengan benar"
        kill $app_pid 2>/dev/null || true
        exit 1
    fi
}

# Fungsi untuk membersihkan saat keluar
cleanup() {
    log_info "🔄 Membersihkan..."
    # Matikan setiap proses Python yang tersisa
    pkill -f "python3.*app.py" 2>/dev/null || true
}

# Siapkan trap untuk pembersihan
trap cleanup EXIT INT TERM

# Eksekusi utama
main() {
    log_info "🎯 Memulai Penyiapan Server API LLaMA"
    log_info "=================================="
    
    # Pindah ke direktori aplikasi
    cd "$APP_DIR" || {
        log_error "Gagal berpindah ke direktori aplikasi: $APP_DIR"
        exit 1
    }
    
    # Jalankan langkah-langkah penyiapan
    check_system_requirements
    setup_environment
    verify_llama_installation || {
        log_error "Verifikasi instalasi LLaMA gagal"
        exit 1
    }
    verify_model_files
    check_python_dependencies || {
        log_error "Pemeriksaan dependensi Python gagal"
        exit 1
    }
    
    # Mulai aplikasi
    start_application
}

# Jalankan fungsi main
main "$@"
