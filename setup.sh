echo "🚀 GGUF Model Setup and Debug Script"
echo "======================================"

# Cek lokasi saat ini
echo "📁 Current directory: $(pwd)"
echo "📁 Contents:"
ls -la

# Cek apakah llama.cpp sudah di-clone
if [ -d "/app/llama.cpp" ]; then
    echo "✅ llama.cpp directory found"
    echo "📁 llama.cpp contents:"
    ls -la /app/llama.cpp/
    
    # Cek build artifacts
    echo "🔍 Looking for executables..."
    find /app/llama.cpp -name "*main*" -o -name "*llama*" | head -10
    
    # Cek jika ada executable
    if [ -f "/app/llama.cpp/llama-cli" ]; then
        echo "✅ Found llama-cli"
        ls -la /app/llama.cpp/llama-cli
    elif [ -f "/app/llama.cpp/main" ]; then
        echo "✅ Found main"
        ls -la /app/llama.cpp/main
    else
        echo "❌ No executable found, attempting build..."
        cd /app/llama.cpp
        make clean
        make -j$(nproc)
        echo "🏗️ Build completed, checking results..."
        ls -la
    fi
else
    echo "❌ llama.cpp directory not found, cloning..."
    git clone https://github.com/ggerganov/llama.cpp.git
    cd llama.cpp
    make -j$(nproc)
fi

# Cek model files
echo "🧠 Looking for GGUF models..."
find /app -name "*.gguf" 2>/dev/null | head -10

# Cek memory dan disk space
echo "💾 System resources:"
df -h /app
# free -h  # Might not work in container

# Test basic functionality
echo "🧪 Testing basic functionality..."
cd /app

if [ -f "app.py" ]; then
    echo "✅ app.py found"
    python -c "import flask; print('✅ Flask installed')"
else
    echo "❌ app.py not found"
fi

echo "======================================"
echo "✨ Setup check completed!"
echo "Start the application with: python app.py"

