FROM ubuntu:22.04

# 1. Cài đặt Go, Node.js, Xvfb và các công cụ bổ trợ
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    python3 python3-pip curl git sudo wget \
    golang-go nodejs npm \
    xvfb libxi6 libgconf-2-4 \
    htop procps \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài đặt thư viện Bot
RUN pip3 install pyTelegramBotAPI flask psutil --break-system-packages

# 3. Tạo file bot.py với tính năng Dashboard và Tự xóa tin nhắn
RUN echo 'import telebot\n\
import os, subprocess, time, psutil\n\
from flask import Flask\n\
from threading import Thread\n\
\n\
TOKEN = os.getenv("TELEGRAM_TOKEN")\n\
ADMIN_ID = os.getenv("ADMIN_ID")\n\
bot = telebot.TeleBot(TOKEN)\n\
app = Flask("")\n\
\n\
@app.route("/")\n\
def home(): return "System Online"\n\
\n\
# Dashboard cập nhật liên tục\n\
def update_dashboard(chat_id, message_id):\n\
    while True:\n\
        try:\n\
            cpu = psutil.cpu_percent()\n\
            ram = psutil.virtual_memory().percent\n\
            uptime = subprocess.check_output("uptime -p", shell=True).decode("utf-8").strip()\n\
            text = f"📊 **SYSTEM MONITOR**\\n"\\\n\
                   f"━━━━━━━━━━━━━━━\\n"\\\n\
                   f"🖥 CPU: {cpu}%\\n"\\\n\
                   f"💾 RAM: {ram}%\\n"\\\n\
                   f"⏱ {uptime}\\n"\\\n\
                   f"🌐 Status: Online\\n"\\\n\
                   f"━━━━━━━━━━━━━━━\\n"\\\n\
                   f"🕒 Last Update: {time.strftime(\"%H:%M:%S\")}"\n\
            bot.edit_message_text(text, chat_id, message_id, parse_mode="Markdown")\n\
        except: pass\n\
        time.sleep(10)\n\
\n\
@bot.message_handler(commands=["start"])\n\
def start_monitor(message):\n\
    sent = bot.send_message(message.chat.id, "📊 Đang khởi tạo Dashboard...")\n\
    Thread(target=update_dashboard, args=(message.chat.id, sent.message_id)).start()\n\
\n\
@bot.message_handler(func=lambda m: str(m.chat.id) == ADMIN_ID)\n\
def exec_command(message):\n\
    cmd = message.text\n\
    # Tự động xóa lệnh của người dùng sau khi nhận\n\
    try: bot.delete_message(message.chat.id, message.message_id)\n\
    except: pass\n\
\n\
    sent_res = bot.send_message(message.chat.id, f"⏳ Exec: `{cmd}`...", parse_mode="Markdown")\n\
    try:\n\
        res = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)\n\
        output = res.decode("utf-8") if res else "Done (No output)"\n\
        bot.edit_message_text(f"✅ `{cmd}`\\n
http://googleusercontent.com/immersive_entry_chip/0

---

### 🌟 Các tính năng mới được thêm vào:

1.  **Dashboard "Như thật":** Khi bạn gõ `/start`, Bot sẽ gửi một tin nhắn Dashboard hiển thị % CPU, % RAM và Uptime. Tin nhắn này sẽ **tự động cập nhật 10 giây một lần** mà không tạo tin nhắn mới.
2.  **Tự xóa lệnh (Clean UI):** Ngay khi bạn gửi một lệnh (ví dụ: `go version`), Bot sẽ xóa tin nhắn đó của bạn ngay lập tức để giữ khung chat sạch sẽ, chỉ còn lại kết quả trả về.
3.  **Công cụ cài sẵn:**
    * **Go:** Kiểm tra bằng `go version`.
    * **Node.js:** Kiểm tra bằng `node -v`.
    * **Xvfb:** Để bạn chạy các ứng dụng cần màn hình ảo (như trình duyệt ẩn danh).
4.  **Giữ container sống:** Vòng lặp Dashboard và Flask server chạy song song giúp Railway luôn thấy container có "nhịp tim", tránh bị giết nhầm.

### 🛠 Cách dùng:
1.  Deploy lên Railway với 2 Variable: `TELEGRAM_TOKEN` và `ADMIN_ID`.
2.  Mở Telegram, gõ `/start` để kích hoạt Dashboard.
3.  Gõ thử: `node -v` hoặc `go version`. Bạn sẽ thấy tin nhắn của mình biến mất và thay bằng kết quả từ Bot.

**Lưu ý về Xvfb:** Để dùng màn hình ảo, bạn hãy gõ lệnh theo cấu trúc: `xvfb-run <lệnh_của_bạn>`. Ví dụ: `xvfb-run node script.js`.

Bản này là "đỉnh" nhất cho việc điều khiển Railway qua Telegram rồi đó! Thử ngay nhé.
