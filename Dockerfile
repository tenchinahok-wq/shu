FROM ubuntu:latest

# 1. Cài đặt các công cụ cơ bản và thư viện cần thiết cho Masscan/Xvfb
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    python3 python3-pip curl git sudo wget \
    nodejs npm \
    xvfb libxi6 libgconf-2-4 \
    htop procps masscan libpcap-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài đặt Go 1.25.0 (Phiên bản cực mới để sửa lỗi package crypto/ecdh và x/net)
RUN wget https://go.dev/dl/go1.25.0.linux-amd64.tar.gz && \
    rm -rf /usr/local/go && tar -C /usr/local -xzf go1.25.0.linux-amd64.tar.gz && \
    rm go1.25.0.linux-amd64.tar.gz
ENV PATH=$PATH:/usr/local/go/bin
ENV GOROOT=/usr/local/go

# 3. Cài đặt thư viện Python
RUN pip3 install pyTelegramBotAPI flask psutil --break-system-packages || pip3 install pyTelegramBotAPI flask psutil

# 4. Tạo script Bot Terminal Live-Stream Log
RUN cat <<'EOF' > /bot.py
import telebot
import os, subprocess, time, psutil, threading
from flask import Flask

# Cấu hình
TOKEN = os.getenv("TELEGRAM_TOKEN")
ADMIN_ID = os.getenv("ADMIN_ID")
bot = telebot.TeleBot(TOKEN, threaded=False)
app = Flask(__name__)

# Trạng thái Terminal
state = {
    "cwd": os.getcwd(),
    "last_dash_id": None
}

@app.route("/")
def health(): return "Terminal Live Online", 200

def get_stats():
    cpu = psutil.cpu_percent(interval=1)
    ram = psutil.virtual_memory().percent
    uptime = subprocess.getoutput("uptime -p")
    return cpu, ram, uptime

# Cập nhật Dashboard hệ thống
def dashboard_loop(chat_id, message_id):
    while True:
        try:
            cpu, ram, uptime = get_stats()
            text = (
                f"🖥️ **LIVE MONITOR**\n"
                f"━━━━━━━━━━━━━━━━━━━━\n"
                f"📂 **CWD:** `{state['cwd']}`\n"
                f"📟 **CPU:** `{cpu}%`  |  🧠 **RAM:** `{ram}%`\n"
                f"⏱️ **{uptime}**\n"
                f"━━━━━━━━━━━━━━━━━━━━\n"
                f"🕒 Update: `{time.strftime('%H:%M:%S')}`\n"
                f"💬 *Gõ lệnh Shell để chạy trực tiếp*"
            )
            bot.edit_message_text(text, chat_id, message_id, parse_mode="Markdown")
        except: pass
        time.sleep(15)

@bot.message_handler(commands=["start"])
def start(message):
    if str(message.chat.id) == ADMIN_ID:
        sent = bot.send_message(message.chat.id, "📊 Khởi tạo Console...")
        state["last_dash_id"] = sent.message_id
        threading.Thread(target=dashboard_loop, args=(message.chat.id, sent.message_id), daemon=True).start()

@bot.message_handler(func=lambda m: str(m.chat.id) == ADMIN_ID)
def execute_live(message):
    cmd = message.text.strip()
    try: bot.delete_message(message.chat.id, message.message_id)
    except: pass

    # Xử lý lệnh CD (Chuyển thư mục)
    if cmd.startswith("cd "):
        target = cmd[3:].strip()
        new_path = os.path.abspath(os.path.join(state["cwd"], target))
        if os.path.isdir(new_path):
            state["cwd"] = new_path
            msg = bot.send_message(message.chat.id, f"📂 Chuyển thư mục sang: `{state['cwd']}`", parse_mode="Markdown")
            threading.Timer(3, lambda: bot.delete_message(message.chat.id, msg.message_id)).start()
        return

    # Khởi tạo tin nhắn log trực tiếp
    status_msg = bot.send_message(message.chat.id, f"🚀 **Running:** `{cmd}`\n`────────────────────`\n⌛ *Đang kết nối...*", parse_mode="Markdown")
    
    def run_and_stream():
        full_output = ""
        last_update_time = 0
        
        try:
            # Chạy subprocess với stdout là PIPE để đọc từng dòng
            process = subprocess.Popen(
                cmd, shell=True, cwd=state["cwd"],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, 
                text=True, bufsize=1, universal_newlines=True
            )

            # Đọc log trực tiếp
            for line in iter(process.stdout.readline, ''):
                full_output += line
                current_time = time.time()
                
                # Giới hạn tần suất cập nhật Telegram (tránh bị Rate Limit)
                if current_time - last_update_time > 1.5:
                    display_text = full_output[-3500:] # Lấy 3500 ký tự cuối để không bị quá giới hạn
                    try:
                        bot.edit_message_text(
                            f"⚡ **Exec:** `{cmd}`\n`────────────────────`\n```\n{display_text}```\n`────────────────────`\n📡 *Đang cập nhật trực tiếp...*",
                            message.chat.id, status_msg.message_id, parse_mode="Markdown"
                        )
                        last_update_time = current_time
                    except: pass
            
            process.stdout.close()
            process.wait()

            # Kết thúc lệnh, hiển thị kết quả cuối cùng
            final_text = full_output if full_output else "Done (No output)"
            bot.edit_message_text(
                f"✅ **Finish:** `{cmd}`\n`────────────────────`\n
