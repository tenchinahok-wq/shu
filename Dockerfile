FROM ubuntu:22.04

# 1. Cài đặt các công cụ cơ bản và thư viện hệ thống
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    python3 python3-pip curl git sudo wget \
    nodejs npm \
    xvfb libxi6 libgconf-2-4 \
    htop procps masscan libpcap-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài đặt Go 1.25.0 (Bản mới nhất, hỗ trợ mọi package hiện đại)
RUN wget https://go.dev/dl/go1.25.0.linux-amd64.tar.gz && \
    rm -rf /usr/local/go && tar -C /usr/local -xzf go1.25.0.linux-amd64.tar.gz && \
    rm go1.25.0.linux-amd64.tar.gz
ENV PATH=$PATH:/usr/local/go/bin
ENV GOROOT=/usr/local/go

# 3. Cài đặt thư viện Python cho Bot
RUN pip3 install pyTelegramBotAPI flask psutil --break-system-packages || pip3 install pyTelegramBotAPI flask psutil

# 4. Tạo script Bot Terminal Live-Log (Dùng printf để tránh lỗi heredoc)
RUN printf 'import telebot\n\
import os, subprocess, time, psutil, threading\n\
from flask import Flask\n\
\n\
TOKEN = os.getenv("TELEGRAM_TOKEN")\n\
ADMIN_ID = os.getenv("ADMIN_ID")\n\
bot = telebot.TeleBot(TOKEN, threaded=False)\n\
app = Flask(__name__)\n\
\n\
state = {"cwd": os.getcwd()}\n\
\n\
@app.route("/")\n\
def health(): return "Live Terminal Online", 200\n\
\n\
def get_stats():\n\
    return psutil.cpu_percent(interval=None), psutil.virtual_memory().percent, subprocess.getoutput("uptime -p")\n\
\n\
def dashboard_loop(chat_id, message_id):\n\
    while True:\n\
        try:\n\
            cpu, ram, uptime = get_stats()\n\
            text = (f"🖥️ **LIVE MONITOR**\\n━━━━━━━━━━━━━━━━━━━━\\n"\n\
                    f"📂 **Dir:** `{state[\"cwd\"]}`\\n"\n\
                    f"📟 **CPU:** `{cpu}%%` | 🧠 **RAM:** `{ram}%%`\\n"\n\
                    f"⏱️ **{uptime}**\\n━━━━━━━━━━━━━━━━━━━━\\n"\n\
                    f"🕒 Update: `{time.strftime(\"%%H:%%M:%%S\")}`")\n\
            bot.edit_message_text(text, chat_id, message_id, parse_mode="Markdown")\n\
        except: pass\n\
        time.sleep(15)\n\
\n\
@bot.message_handler(commands=["start"])\n\
def start(message):\n\
    if str(message.chat.id) == ADMIN_ID:\n\
        sent = bot.send_message(message.chat.id, "📊 Đang khởi tạo...")\n\
        threading.Thread(target=dashboard_loop, args=(message.chat.id, sent.message_id), daemon=True).start()\n\
\n\
@bot.message_handler(func=lambda m: str(m.chat.id) == ADMIN_ID)\n\
def exec_live(message):\n\
    cmd = message.text.strip()\n\
    try: bot.delete_message(message.chat.id, message.message_id)\n\
    except: pass\n\
\n\
    if cmd.startswith("cd "):\n\
        path = os.path.abspath(os.path.join(state["cwd"], cmd[3:].strip()))\n\
        if os.path.isdir(path): state["cwd"] = path\n\
        return\n\
\n\
    status_msg = bot.send_message(message.chat.id, f"🚀 **Exec:** `{cmd}`\\n`────────────────────`\\n📡 *Đang kết nối...*", parse_mode="Markdown")\n\
\n\
    def run():\n\
        full_out = ""\n\
        last_up = 0\n\
        try:\n\
            p = subprocess.Popen(cmd, shell=True, cwd=state["cwd"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)\n\
            for line in iter(p.stdout.readline, ""):\n\
                full_out += line\n\
                if time.time() - last_up > 1.5:\n\
                    try:\n\
                        bot.edit_message_text(f"⚡ **Running:** `{cmd}`\\n`────────────────────`\\n
