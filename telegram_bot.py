import os
import logging
import httpx
from flask import Flask, request, jsonify
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes

# Konfigurasi logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger(__name__)

# URL API LLaMA.
# Perhatikan: Kami menggunakan 'http://127.0.0.1:8080' karena keduanya berada di kontainer yang sama
LLAMA_API_URL = "http://127.0.0.1:8080/generate"

# Token Bot Telegram dari variabel lingkungan
TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN")

# URL yang digunakan untuk webhook.
WEBHOOK_URL_PATH = "/telegram"

# Inisialisasi aplikasi Flask
app = Flask(__name__)

# Inisialisasi Application builder untuk python-telegram-bot
application = Application.builder().token(TELEGRAM_BOT_TOKEN).build()

# Fungsi handler untuk perintah /start
async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text('Halo! Saya adalah bot LLaMA. Kirimkan saya sebuah prompt dan saya akan mencoba menjawabnya.')

# Fungsi handler untuk perintah /help
async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text('Kirimkan saya teks apa pun dan saya akan memprosesnya dengan model LLaMA.')

# Fungsi handler untuk pesan teks
async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_prompt = update.message.text
    chat_id = update.message.chat_id

    processing_message = await context.bot.send_message(
        chat_id=chat_id,
        text="Sedang memproses permintaan Anda... Tunggu sebentar."
    )

    try:
        api_data = {
            "prompt": user_prompt,
            "max_tokens": 512,
            "temperature": 0.8
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.post(LLAMA_API_URL, json=api_data, timeout=300)

        if response.status_code == 200:
            result = response.json()
            if result.get("success"):
                generated_text = result.get("text", "Tidak dapat menghasilkan teks.")
                await context.bot.send_message(
                    chat_id=chat_id,
                    text=generated_text
                )
            else:
                error_message = result.get("error", "Terjadi kesalahan yang tidak diketahui.")
                await context.bot.send_message(
                    chat_id=chat_id,
                    text=f"API LLaMA mengembalikan kesalahan: {error_message}"
                )
        else:
            await context.bot.send_message(
                chat_id=chat_id,
                text=f"API LLaMA tidak dapat dijangkau. Kode status: {response.status_code}"
            )

    except httpx.HTTPError as http_err:
        logger.error(f"HTTP Error: {http_err}")
        await context.bot.send_message(
            chat_id=chat_id,
            text="Terjadi kesalahan saat mencoba terhubung ke API LLaMA. Pastikan API Anda berjalan."
        )
    except Exception as e:
        logger.error(f"An unexpected error occurred: {e}")
        await context.bot.send_message(
            chat_id=chat_id,
            text="Terjadi kesalahan internal. Silakan coba lagi nanti."
        )
    finally:
        await context.bot.delete_message(
            chat_id=chat_id,
            message_id=processing_message.message_id
        )

# Tambahkan handler bot
application.add_handler(CommandHandler("start", start_command))
application.add_handler(CommandHandler("help", help_command))
application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))

@app.route(WEBHOOK_URL_PATH, methods=['POST'])
async def telegram_webhook():
    if request.method == "POST":
        update = Update.de_json(request.get_json(force=True), application.bot)
        await application.process_update(update)
        return jsonify({"status": "success"})

@app.route("/", methods=["GET"])
def index():
    return jsonify({"status": "Telegram bot is running"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
