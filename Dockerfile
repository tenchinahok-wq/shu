FROM ubuntu:22.04

# 1. Cài đặt các công cụ: Go, Node.js, Xvfb, Python và các thư viện hệ thống
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    python3 python3-pip curl git sudo wget \
    golang-go nodejs npm \
    xvfb libxi6 libgconf-2-4 \
    htop procps \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài đặt thư viện cho Bot Telegram và Monitoring
RUN pip3 install pyTelegramBotAPI flask psutil --break-system-packages

# 3. Tạo file bot.py trực tiếp (Sử dụng cat để nội dung sạch sẽ nhất)
RUN cat <<'EOF' > /bot.py
import telebot
import os, subprocess, time, psutil
from flask import Flask
from threading import Thread

# Lấy cấu hình từ Railway Variables
TOKEN = os.getenv("TELEGRAM_TOKEN")
ADMIN_ID = os.getenv("ADMIN_ID")

bot = telebot.TeleBot(TOKEN)
app = Flask(__name__)

@app.route("/")
def health():
    return "Bot is Running", 200

def get_system_stats():
    cpu = psutil.cpu_percent(interval=1)
    ram = psutil.virtual_memory().percent
    try:
        uptime = subprocess.check_output("uptime -p", shell=True).decode("utf-8").strip()
    except:
        uptime = "N/A"
    return cpu, ram, uptime

# Hàm cập nhật Dashboard tự động
def update_dashboard(chat_id, message_id):
    while True:
        try:
            cpu, ram, uptime = get_system_stats()
            text = (
                "🖥️ **HỆ THỐNG GIÁM SÁT REAL-TIME**\n"
                "━━━━━━━━━━━━━━━━━━━━\n"
                f"📟 **CPU:** `{cpu}%`\n"
                f"🧠 **RAM:** `{ram}%`\n"
                f"⏱️ **{uptime}**\n"
                "━━━━━━━━━━━━━━━━━━━━\n"
                f"🕒 Cập nhật: `{time.strftime('%H:%M:%S')}`\n"
                "💬 *Gõ lệnh trực tiếp để thực thi*"
            )
            bot.edit_message_text(text, chat_id, message_id, parse_mode="Markdown")
        except:
            pass
        time.sleep(10)

@bot.message_handler(commands=["start"])
def start(message):
    if str(message.chat.id) == ADMIN_ID:
        sent = bot.send_message(message.chat.id, "📊 Đang khởi tạo Dashboard...")
        t = Thread(target=update_dashboard, args=(message.chat.id, sent.message_id))
        t.daemon = True
        t.start()
    else:
        bot.reply_to(message, "❌ Quyền truy cập bị từ chối.")

@bot.message_handler(func=lambda m: str(m.chat.id) == ADMIN_ID)
def run_command(message):
    cmd = message.text
    # 1. Tự động xóa tin nhắn lệnh của người dùng cho sạch UI
    try:
        bot.delete_message(message.chat.id, message.message_id)
    except:
        pass

    # 2. Thông báo đang thực thi
    status_msg = bot.send_message(message.chat.id, f"⏳ Đang thực thi: `{cmd}`", parse_mode="Markdown")

    try:
        # Thực thi lệnh và lấy kết quả (Timeout 60s tránh treo bot)
        result = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, timeout=60)
        output = result.decode("utf-8") if result else "Thành công (Không có output)"
        
        # Cắt ngắn nếu output quá dài
        if len(output) > 3500:
            output = output[:3500] + "\n[...Dữ liệu quá dài...]"
        
        bot.edit_message_text(f"✅ `{cmd}`\n```\n{output}```", message.chat.id, status_msg.message_id, parse_mode="Markdown")
    except subprocess.CalledProcessError as e:
        err_out = e.output.decode() if e.output else str(e)
        bot.edit_message_text(f"❌ Lỗi thực thi `{cmd}`:\n```\n{err_out}```", message.chat.id, status_msg.message_id, parse_mode="Markdown")
    except Exception as e:
        bot.edit_message_text(f"❌ Lỗi hệ thống: `{str(e)}`", message.chat.id, status_msg.message_id, parse_mode="Markdown")

def run_flask():
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)

if __name__ == "__main__":
    # Chạy Web Server cho Railway Healthcheck ở luồng riêng
    Thread(target=run_flask, daemon=True).start()
    print("🤖 Bot Telegram Shell đang hoạt động...")
    bot.infinity_polling()
EOF

# Port cho Railway
EXPOSE 8080

# Chạy bot bằng Python
CMD ["python3", "/bot.py"]
