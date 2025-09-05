# Menggunakan image dasar Ubuntu yang stabil
FROM ubuntu:22.04

# Mencegah prompt interaktif selama instalasi paket
ENV DEBIAN_FRONTEND=noninteractive

# Menginstal dependensi sistem yang diperlukan
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    gcc \
    g++ \
    make \
    pkg-config \
    libopenblas-dev \
    libcurl4-openssl-dev \
    git-lfs \
    && rm -rf /var/lib/apt/lists/*

# Set working directory utama
WORKDIR /app

# Mengkloning llama.cpp dan membangunnya
RUN git clone https://github.com/ggerganov/llama.cpp.git
WORKDIR /app/llama.cpp

# Membangun llama.cpp dengan CMake
RUN mkdir -p build && cd build && \
    cmake .. -DLLAMA_OPENBLAS=ON && \
    cmake --build . --config Release --parallel $(nproc)

# Kembali ke direktori aplikasi utama
WORKDIR /app

# Membuat direktori models
RUN mkdir -p /app/models

# Mengunduh model GGUF
RUN wget -O models/model.gguf "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf" || \
    wget -O models/model.gguf "https://huggingface.co/microsoft/DialoGPT-small/resolve/main/pytorch_model.bin" || \
    echo "Model download failed - will use local model if available"

# Menyalin file aplikasi
COPY requirements.txt .
COPY app.py .
COPY setup.sh .

# Menginstal dependensi Python
RUN pip install --no-cache-dir --upgrade pip
RUN pip install --no-cache-dir -r requirements.txt

# Memberi izin eksekusi pada skrip setup
RUN chmod +x setup.sh

# Menetapkan variabel lingkungan
ENV PYTHONUNBUFFERED=1
ENV PORT=7860
ENV PYTHONPATH=/app

# Mengekspos port
EXPOSE 7860

# Menambahkan healthcheck untuk memeriksa status aplikasi
HEALTHCHECK --interval=30s --timeout=30s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:7860/health || exit 1

# Menjalankan skrip setup sebagai titik masuk utama
CMD ["./setup.sh"]