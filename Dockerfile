# Use a modern, stable base image
FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies for Python, Flask, and llama.cpp
RUN apt-get update && apt-get install -y --no-install-recommends \
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
    git-lfs \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/python3 /usr/bin/python \
    && ln -s /usr/bin/pip3 /usr/bin/pip

# Set working directory for the application
WORKDIR /app

# Clone llama.cpp and build it with OpenBLAS for performance
RUN git clone https://github.com/ggerganov/llama.cpp.git
WORKDIR /app/llama.cpp
RUN make clean && LLAMA_OPENBLAS=1 make -j$(nproc)

# Download a small, reliable GGUF model to the designated models directory
WORKDIR /app
RUN mkdir -p /app/models
RUN wget -O models/model.gguf "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"

# Copy the application files
COPY requirements.txt .
COPY app.py .
COPY setup.sh .
RUN chmod +x setup.sh

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Expose the port used by the Flask app
EXPOSE 7860

# Define a healthcheck to ensure the container is ready
HEALTHCHECK --interval=30s --timeout=30s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:7860/health || exit 1

# Define the entrypoint to run the setup script, which then starts the app
CMD ["./setup.sh"]
