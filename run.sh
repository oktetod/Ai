#!/bin/bash
set -e

# Jalankan skrip setup untuk mengunduh model
./setup.sh

echo "Starting both LLaMA API and Telegram Bot services..."

# Mulai server API LLaMA dengan Gunicorn di port 7860
gunicorn -w 4 --bind 0.0.0.0:7860 app:app &

# Mulai server bot Telegram dengan Gunicorn di port 8080 (port utama yang terekspos)
gunicorn -w 4 --bind 0.0.0.0:8080 telegram_bot:app &

# Tunggu hingga salah satu proses di latar belakang berhenti
wait -n

echo "One of the services has stopped. Shutting down."
exit 1
