FROM ubuntu:latest

# 1. Cài đặt Python và các công cụ cần thiết
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    python3 python3-pip curl git sudo \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài đặt thư viện Bot Telegram
RUN pip3 install pyTelegramBotAPI flask --break-system-packages

# 3. Tạo file bot.py trực tiếp
RUN echo 'import telebot\n\
import os\n\
import subprocess\n\
from flask import Flask\n\
from threading import Thread\n\
\n\
# Lấy Token và ID Admin từ Variable Railway\n\
TOKEN = os.getenv("TELEGRAM_TOKEN")\n\
ADMIN_ID = os.getenv("ADMIN_ID") # Để chỉ mình bạn dùng được\n\
\n\
bot = telebot.TeleBot(TOKEN)\n\
app = Flask("")\n\
\n\
@app.route("/")\n\
def home():\n\
    return "Bot is Running!"\n\
\n\
@bot.message_handler(commands=["start"])\n\
def send_welcome(message):\n\
    bot.reply_to(message, "🚀 Bot Remote Shell đã sẵn sàng! Gõ lệnh để thực thi.")\n\
\n\
@bot.message_handler(func=lambda message: str(message.chat.id) == ADMIN_ID)\n\
def run_command(message):\n\
    try:\n\
        # Thực thi lệnh shell từ tin nhắn\n\
        cmd = message.text\n\
        result = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)\n\
        output = result.decode("utf-8")\n\
        if not output:\n\
            output = "Done (No output)"\n\
        bot.reply_to(message, f"```\\n{output}```", parse_mode="Markdown")\n\
    except Exception as e:\n\
        bot.reply_to(message, f"❌ Lỗi: {str(e)}")\n\
\n\
def run_flask():\n\
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))\n\
\n\
if __name__ == "__main__":\n\
    # Chạy Flask ở luồng riêng để Railway Healthcheck không báo lỗi\n\
    Thread(target=run_flask).start()\n\
    print("🤖 Bot đang lắng nghe...")\n\
    bot.infinity_polling()' > /bot.py

# Railway dùng cổng 8080 cho Healthcheck
EXPOSE 8080

CMD ["python3", "/bot.py"]
