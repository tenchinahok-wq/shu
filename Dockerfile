FROM ubuntu:latest

# 1. Cài đặt các công cụ cơ bản
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    python3 python3-pip curl git sudo wget \
    nodejs npm \
    xvfb libxi6 libgconf-2-4 \
    htop procps \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài đặt Go 1.23.2 (Bản mới nhất để hỗ trợ crypto/ecdh, slices...)
RUN wget https://go.dev/dl/go1.23.2.linux-amd64.tar.gz && \
    rm -rf /usr/local/go && tar -C /usr/local -xzf go1.23.2.linux-amd64.tar.gz && \
    rm go1.23.2.linux-amd64.tar.gz
ENV PATH=$PATH:/usr/local/go/bin

# 3. Cài đặt thư viện Python
RUN pip3 install pyTelegramBotAPI flask psutil

# 4. Tạo script Bot điều khiển (Cập nhật kết quả vào tin nhắn cũ)
RUN cat <<'EOF' > /bot.py
import telebot
import os, subprocess, time, psutil
from flask import Flask
from threading import Thread

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

# Cập nhật Dashboard (Tin nhắn theo dõi hệ thống)
def update_dashboard(chat_id, message_id):
    while True:
        try:
            cpu, ram, uptime = get_system_stats()
            text = (
                "🖥️ **HỆ THỐNG GIÁM SÁT REAL-TIME**\n"
                "━━━━━━━━━━━━━━━━━━━━\n"
                f"📟 **CPU:** `{cpu}%`  |  🧠 **RAM:** `{ram}%`\n"
                f"⏱️ **Uptime:** {uptime}\n"
                "━━━━━━━━━━━━━━━━━━━━\n"
                f"🕒 Cập nhật lúc: `{time.strftime('%H:%M:%S')}`\n"
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
    # 1. Xóa lệnh người dùng gửi để sạch UI
    try:
        bot.delete_message(message.chat.id, message.message_id)
    except:
        pass

    # 2. Gửi tin nhắn trạng thái ban đầu
    status_msg = bot.send_message(message.chat.id, f"⏳ Đang thực thi: `{cmd}`...", parse_mode="Markdown")

    try:
        # 3. Thực thi lệnh
        process = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
        
        # Đợi lệnh chạy và lấy kết quả
        output, _ = process.communicate(timeout=120)
        output_str = output.decode("utf-8") if output else "Thành công (Không có output)"
        
        # Cắt ngắn nếu quá dài
        if len(output_str) > 3800:
            output_str = output_str[:3800] + "\n[...Dữ liệu quá dài...]"
        
        # 4. CẬP NHẬT KẾT QUẢ VÀO CHÍNH TIN NHẮN ĐÓ
        bot.edit_message_text(
            f"✅ **Lệnh:** `{cmd}`\n━━━━━━━━━━━━━━━━━━━━\n```\n{output_str}```", 
            message.chat.id, 
            status_msg.message_id, 
            parse_mode="Markdown"
        )
    except subprocess.TimeoutExpired:
        process.kill()
        bot.edit_message_text(f"❌ Lỗi: Lệnh `{cmd}` bị quá tải (Timeout 120s)", message.chat.id, status_msg.message_id)
    except Exception as e:
        bot.edit_message_text(f"❌ Lỗi khi chạy `{cmd}`:\n```\n{str(e)}```", message.chat.id, status_msg.message_id, parse_mode="Markdown")

def run_flask():
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)

if __name__ == "__main__":
    Thread(target=run_flask, daemon=True).start()
    print("🤖 Bot Telegram Shell đang hoạt động...")
    bot.infinity_polling()
EOF

# Port cho Railway
EXPOSE 8080

# Chạy bot bằng Python
CMD ["python3", "/bot.py"]
