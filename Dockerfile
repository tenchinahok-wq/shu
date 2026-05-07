```dockerfile
FROM ubuntu:22.04

# 1. Cài đặt các công cụ: Go, Node.js, Xvfb, Python và các thư viện hệ thống
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    python3 python3-pip curl git sudo wget \
    golang-go nodejs npm \
    xvfb libxi6 libgconf-2-4 \
    htop procps \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài đặt thư viện cho Bot Telegram và Dashboard
RUN pip3 install pyTelegramBotAPI flask psutil --break-system-packages

# 3. Tạo file bot.py trực tiếp bên trong Dockerfile
RUN echo 'import telebot\n\
import os, subprocess, time, psutil\n\
from flask import Flask\n\
from threading import Thread\n\
\n\
# Lấy cấu hình từ Railway Variables\n\
TOKEN = os.getenv("TELEGRAM_TOKEN")\n\
ADMIN_ID = os.getenv("ADMIN_ID")\n\
\n\
bot = telebot.TeleBot(TOKEN)\n\
app = Flask(__name__)\n\
\n\
@app.route("/")\n\
def health():\n\
    return "Status: OK", 200\n\
\n\
# Hàm cập nhật Dashboard tự động\n\
def update_dashboard(chat_id, message_id):\n\
    while True:\n\
        try:\n\
            cpu = psutil.cpu_percent(interval=1)\n\
            ram = psutil.virtual_memory().percent\n\
            disk = psutil.disk_usage("/").percent\n\
            # Lấy uptime hệ thống\n\
            uptime_raw = subprocess.check_output("uptime -p", shell=True).decode("utf-8").strip()\n\
            \n\
            dashboard_text = (\n\
                "🖥️ **HỆ THỐNG ĐANG CHẠY**\\n"\n\
                "━━━━━━━━━━━━━━━━━━━━\\n"\n\
                f"📟 **CPU:** {cpu}%\\n"\n\
                f"🧠 **RAM:** {ram}%\\n"\n\
                f"💽 **Disk:** {disk}%\\n"\n\
                f"⏱️ **{uptime_raw}**\\n"\n\
                "━━━━━━━━━━━━━━━━━━━━\\n"\n\
                f"🕒 Cập nhật: {time.strftime(\"%H:%M:%S\")}\\n"\n\
                "💬 *Gõ lệnh trực tiếp để thực thi*"\n\
            )\n\
            bot.edit_message_text(dashboard_text, chat_id, message_id, parse_mode="Markdown")\n\
        except Exception as e:\n\
            print(f"Dashboard Error: {e}")\n\
        time.sleep(10)\n\
\n\
@bot.message_handler(commands=["start"])\n\
def start(message):\n\
    if str(message.chat.id) == ADMIN_ID:\n\
        sent = bot.send_message(message.chat.id, "📊 Đang khởi tạo Dashboard...")\n\
        Thread(target=update_dashboard, args=(message.chat.id, sent.message_id), daemon=True).start()\n\
    else:\n\
        bot.reply_to(message, "❌ Quyền truy cập bị từ chối.")\n\
\n\
@bot.message_handler(func=lambda m: str(m.chat.id) == ADMIN_ID)\n\
def run_command(message):\n\
    cmd = message.text\n\
    # 1. Tự động xóa tin nhắn lệnh của người dùng\n\
    try: bot.delete_message(message.chat.id, message.message_id)\n\
    except: pass\n\
\n\
    # 2. Thông báo đang thực thi\n\
    exec_msg = bot.send_message(message.chat.id, f"⏳ Đang chạy: `{cmd}`", parse_mode="Markdown")\n\
\n\
    try:\n\
        # Thực thi lệnh và lấy kết quả\n\
        result = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)\n\
        output = result.decode("utf-8") if result else "Thực thi thành công (Không có output)"\n\
        \n\
        # Cắt ngắn nếu output quá dài (> 3500 ký tự)\n\
        if len(output) > 3500: output = output[:3500] + "...\\n[Output quá dài]"\n\
        \n\
        bot.edit_message_text(f"✅ `{cmd}`\\n```\\n{output}```", message.chat.id, exec_msg.message_id, parse_mode="Markdown")\n\
    except Exception as e:\n\
        error_msg = str(e.output.decode() if hasattr(e, \"output\") else e)\n\
        bot.edit_message_text(f"❌ Lỗi khi chạy `{cmd}`:\\n```\\n{error_msg}```", message.chat.id, exec_msg.message_id, parse_mode="Markdown")\n\
\n\
def run_web():\n\
    port = int(os.environ.get("PORT", 8080))\n\
    app.run(host="0.0.0.0", port=port)\n\
\n\
if __name__ == "__main__":\n\
    # Chạy Web Server cho Railway Healthcheck\n\
    Thread(target=run_web, daemon=True).start()\n\
    print("🤖 Bot is live...")\n\
    bot.infinity_polling()' > /bot.py

# Railway Port
EXPOSE 8080

# Chạy bot bằng Python
CMD ["python3", "/bot.py"]

```
