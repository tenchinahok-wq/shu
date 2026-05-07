FROM ubuntu:22.04

# 1. Cài đặt các công cụ cơ bản
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    python3 python3-pip curl git sudo wget \
    nodejs npm \
    xvfb libxi6 libgconf-2-4 \
    htop procps \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài đặt Go 1.23.2 chuẩn (Dùng cho 8.go không bị lỗi crypto/ecdh)
RUN wget https://go.dev/dl/go1.23.2.linux-amd64.tar.gz && \
    rm -rf /usr/local/go && tar -C /usr/local -xzf go1.23.2.linux-amd64.tar.gz && \
    rm go1.23.2.linux-amd64.tar.gz
ENV PATH=$PATH:/usr/local/go/bin

# 3. Cài đặt thư viện Bot (Xử lý lỗi tương thích pip trên Ubuntu mới)
RUN pip3 install pyTelegramBotAPI flask psutil || pip3 install pyTelegramBotAPI flask psutil --break-system-packages

# 4. Tạo script Bot điều khiển Shell qua Telegram
RUN cat <<'EOF' > /bot.py
import telebot
import os, subprocess, time, psutil
from flask import Flask
from threading import Thread

TOKEN = os.getenv("TELEGRAM_TOKEN")
ADMIN_ID = os.getenv("ADMIN_ID")

bot = telebot.TeleBot(TOKEN, threaded=False)
app = Flask(__name__)

@app.route("/")
def health():
    return "Bot is Live", 200

def get_stats():
    cpu = psutil.cpu_percent(interval=1)
    ram = psutil.virtual_memory().percent
    try:
        uptime = subprocess.check_output("uptime -p", shell=True).decode("utf-8").strip()
    except:
        uptime = "N/A"
    return cpu, ram, uptime

# Hàm cập nhật Dashboard (Bảng theo dõi hệ thống)
def update_dashboard(chat_id, message_id):
    while True:
        try:
            cpu, ram, uptime = get_stats()
            text = (
                "🖥️ **HỆ THỐNG GIÁM SÁT REAL-TIME**\n"
                "━━━━━━━━━━━━━━━━━━━━\n"
                f"📟 **CPU:** `{cpu}%`  |  🧠 **RAM:** `{ram}%`\n"
                f"⏱️ **Uptime:** {uptime}\n"
                "━━━━━━━━━━━━━━━━━━━━\n"
                f"🕒 Cập nhật: `{time.strftime('%H:%M:%S')}`\n"
                "💬 *Gõ lệnh Shell để thực thi*"
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
        bot.reply_to(message, "❌ Truy cập bị từ chối.")

@bot.message_handler(func=lambda m: str(m.chat.id) == ADMIN_ID)
def run_command(message):
    cmd = message.text
    # 1. Xóa lệnh của người dùng để sạch khung chat
    try:
        bot.delete_message(message.chat.id, message.message_id)
    except:
        pass

    # 2. Gửi tin nhắn trạng thái
    status_msg = bot.send_message(message.chat.id, f"⏳ Executing: `{cmd}`...", parse_mode="Markdown")

    try:
        # 3. Thực thi lệnh Shell
        process = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
        output, _ = process.communicate(timeout=120)
        output_str = output.decode("utf-8") if output else "Done (No output)"
        
        # Giới hạn độ dài tin nhắn Telegram
        if len(output_str) > 3800:
            output_str = output_str[:3800] + "\n[...Dữ liệu quá dài...]"
        
        # 4. CẬP NHẬT KẾT QUẢ VÀO TIN NHẮN CŨ
        bot.edit_message_text(
            f"✅ **Lệnh:** `{cmd}`\n━━━━━━━━━━━━━━━━━━━━\n```\n{output_str}```", 
            message.chat.id, 
            status_msg.message_id, 
            parse_mode="Markdown"
        )
    except Exception as e:
        bot.edit_message_text(f"❌ Error: `{str(e)}`", message.chat.id, status_msg.message_id)

def run_flask():
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)

if __name__ == "__main__":
    # Chạy Web Server cho Railway Healthcheck
    Thread(target=run_flask, daemon=True).start()
    print("🤖 Bot Shell is starting...")
    
    # Vòng lặp chống lỗi 409 Conflict khi Railway Deploy
    while True:
        try:
            bot.polling(none_stop=True, interval=2, timeout=20)
        except:
            time.sleep(5)
EOF

# Port cho Railway
EXPOSE 8080

# Chạy bằng Python 3
CMD ["python3", "/bot.py"]
