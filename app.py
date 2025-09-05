import os
import requests
import subprocess
import logging
import json
import time
from flask import Flask, request, jsonify
import urllib3

# Menonaktifkan peringatan SSL
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Token API bot Telegram Anda.
# Token ini sekarang disematkan langsung dalam kode.
TELEGRAM_API_TOKEN = "8305182212:AAGUVp3D7eP3niC2dlZFIib2nbINl5DXXc8"

# Lokasi yang mungkin dari executable llama.cpp dan model GGUF.
# Ini harus sesuai dengan Dockerfile Anda.
POSSIBLE_LLAMA_PATHS = [
    "/app/llama.cpp/build/bin/llama-cli",
    "/app/llama.cpp/build/bin/main",
    "/app/llama.cpp/llama-cli",
    "/app/llama.cpp/main",
]

POSSIBLE_MODEL_PATHS = [
    "/app/models/model.gguf",
    "/app/models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
]

# Variabel global untuk jalur
LLAMA_CPP_PATH = None
MODEL_PATH = None

def find_executable_paths():
    """Mencari executable llama.cpp dan file model."""
    global LLAMA_CPP_PATH, MODEL_PATH
    
    logger.info("🔍 Mencari executable llama.cpp...")
    for path in POSSIBLE_LLAMA_PATHS:
        if os.path.exists(path) and os.access(path, os.X_OK):
            LLAMA_CPP_PATH = path
            logger.info(f"✅ Executable ditemukan di: {path}")
            break

    logger.info("🔍 Mencari file model...")
    for path in POSSIBLE_MODEL_PATHS:
        if os.path.exists(path) and os.path.getsize(path) > 1024 * 1024:
            MODEL_PATH = path
            logger.info(f"✅ Model ditemukan di: {path}")
            break

def send_telegram_message(chat_id, text):
    """Fungsi untuk mengirim pesan kembali ke Telegram menggunakan urllib3."""
    http = urllib3.PoolManager()
    
    # Gunakan alamat IP statis untuk melewati masalah DNS
    url = f"https://149.154.167.220/bot{TELEGRAM_API_TOKEN}/sendMessage"
    
    payload = {
        "chat_id": chat_id,
        "text": text
    }
    
    try:
        response = http.request(
            "POST",
            url,
            fields=payload,
            timeout=urllib3.Timeout(connect=10.0, read=10.0)
        )
        if response.status == 200:
            logger.info(f"📤 Pesan berhasil dikirim ke chat ID {chat_id}")
        else:
            logger.error(f"❌ Gagal mengirim pesan Telegram. Status: {response.status}, Respon: {response.data.decode('utf-8')}")
    except urllib3.exceptions.MaxRetryError as e:
        logger.error(f"❌ Gagal mengirim pesan Telegram: {e}")

def generate_with_llama(prompt, max_tokens=512, temperature=0.8):
    """Menghasilkan teks menggunakan subprocess llama.cpp lokal."""
    if not LLAMA_CPP_PATH:
        return "❌ Executable llama.cpp tidak ditemukan."
    if not MODEL_PATH:
        return "❌ File model tidak ditemukan."

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
        
        logger.info(f"🚀 Menjalankan llama.cpp dengan prompt: {prompt[:50]}...")
        
        process = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=120,
            check=False
        )

        if process.returncode != 0:
            logger.error(f"⚠️ Proses mengembalikan kode keluar bukan nol: {process.returncode}")
            logger.error(f"STDERR: {process.stderr}")
            return "⚠️ Eksekusi model gagal. Periksa log untuk detail."

        output = process.stdout.strip()
        
        if prompt in output:
            output = output.replace(prompt, "", 1).strip()
            
        if not output:
            return "🤔 Model menghasilkan respons kosong."
            
        return output

    except subprocess.TimeoutExpired:
        return "⏱️ Permintaan melebihi batas waktu. Model mungkin terlalu lambat untuk prompt yang diberikan."
    except Exception as e:
        logger.error(f"❌ Terjadi kesalahan tak terduga dalam generasi: {e}")
        return f"⚠️ Terjadi kesalahan tak terduga: {str(e)}"

# ---
# Rute Flask
# ---

@app.route("/", methods=["GET"])
def home():
    """Endpoint utama aplikasi."""
    return jsonify({
        "status": "🚀 API dan Bot Telegram online",
        "endpoints": {
            "/": "Halaman ini",
            "/webhook": "Endpoint webhook Telegram"
        }
    })

@app.route("/webhook", methods=["POST"])
def telegram_webhook():
    """Endpoint untuk webhook Telegram."""
    update = request.json
    logger.info("📨 Menerima pembaruan webhook.")
    
    if "message" in update:
        message = update["message"]
        chat_id = message["chat"]["id"]
        prompt = message.get("text", "").strip()
        
        if not prompt:
            send_telegram_message(chat_id, "🤖 Mohon kirim pesan teks untuk mendapatkan respons.")
            return jsonify({"status": "ok"})
            
        # Menghasilkan respons
        response_text = generate_with_llama(prompt)
        
        # Mengirim respons kembali ke Telegram
        send_telegram_message(chat_id, response_text)
        
    return jsonify({"status": "ok"})

@app.route("/health", methods=["GET"])
def health_check():
    """Endpoint pemeriksaan kesehatan."""
    healthy = LLAMA_CPP_PATH is not None and MODEL_PATH is not None
    return jsonify({
        "status": "sehat" if healthy else "tidak sehat",
        "llama_tersedia": LLAMA_CPP_PATH is not None,
        "model_tersedia": MODEL_PATH is not None,
        "siap": healthy
    }), 200 if healthy else 503

if __name__ == "__main__":
    find_executable_paths()
    port = int(os.environ.get("PORT", 7860))
    logger.info(f"🚀 Memulai server di port {port}")
    app.run(host="0.0.0.0", port=port)