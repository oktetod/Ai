#!/bin/bash
set -e

# Kode warna
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Fungsi untuk memverifikasi file model
verify_model_files() {
    log_info "🔍 Memverifikasi file model..."
    
    local model_path="/app/models/model.gguf"
    
    if [[ -f "$model_path" ]]; then
        local file_size=$(du -h "$model_path" | cut -f1)
        log_info "✅ File model ditemukan: $model_path ($file_size)"
        return 0
    else
        log_warn "⚠️ Tidak ada file model yang ditemukan. Mencoba mengunduh..."
        download_model
    fi
}

# Fungsi untuk mengunduh model jika hilang
download_model() {
    log_info "📥 Mengunduh file model..."
    
    mkdir -p "/app/models"
    
    local model_url="https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
    local model_path="/app/models/model.gguf"
    
    if command -v wget >/dev/null 2>&1; then
        log_info "Menggunakan wget untuk mengunduh model..."
        if wget -O "$model_path" "$model_url" --progress=dot:giga --timeout=300 --tries=3; then
            log_info "✅ Model berhasil diunduh"
        else
            log_warn "⚠️ Unduhan model gagal dengan wget, mencoba curl..."
            if command -v curl >/dev/null 2>&1; then
                download_with_curl "$model_url" "$model_path"
            fi
        fi
    elif command -v curl >/dev/null 2>&1; then
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

# Jalankan skrip utama
main() {
    log_info "🎯 Memulai Penyiapan Awal Server"
    log_info "=================================="
    
    # Pindah ke direktori aplikasi
    cd "/app" || {
        log_error "Gagal berpindah ke direktori aplikasi: /app"
        exit 1
    }
    
    # Jalankan langkah-langkah penyiapan
    verify_model_files
    
    log_info "Penyiapan selesai. Menunggu perintah untuk memulai aplikasi..."
}

# Jalankan fungsi main
main "$@"
