
# Sử dụng Ubuntu 24.04 làm nền tảng
FROM ubuntu:24.04

# Ngăn các câu hỏi tương tác khi cài đặt
ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt các công cụ hệ thống và Python
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y \
    python3 python3-pip python3-venv \
    curl wget git htop neofetch \
    build-essential iputils-ping dnsutils net-tools vim \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Thiết lập thư mục làm việc
WORKDIR /app

# 3. Tạo môi trường ảo và cài đặt thư viện Telegram
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir python-telegram-bot --upgrade

# 4. Tạo file bot.py trực tiếp bên trong Dockerfile
# LƯU Ý: Bạn cần thay TOKEN và ID của bạn ở dòng 36 và 38 bên dưới
RUN cat <<'EOF' > /app/bot.py
import asyncio
import os
import logging
from telegram import Update
from telegram.ext import Application, MessageHandler, filters, ContextTypes

# --- CẤU HÌNH ---
TOKEN = "8190267925:AAHHdE2YuYWd9PfPXIILlzP-KA0SmynGhsc"
ALLOWED_USER_ID = 6974873344  # Thay bằng ID Telegram của bạn
LOG_LIMIT = 10 

state = {"last_msg_id": None}

logging.basicConfig(level=logging.INFO)

async def run_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ALLOWED_USER_ID:
        return

    command = update.message.text
    chat_id = update.effective_chat.id
    
    # Xóa log cũ trước khi chạy lệnh mới
    if state["last_msg_id"]:
        try:
            await context.bot.delete_message(chat_id=chat_id, message_id=state["last_msg_id"])
        except:
            pass

    log_msg = await update.message.reply_text(f"⌛ Exec: `{command}`...", parse_mode='Markdown')
    state["last_msg_id"] = log_msg.message_id

    process = await asyncio.create_subprocess_shell(
        command, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT
    )

    lines = []
    
    async def update_ui():
        last_text = ""
        while process.returncode is None:
            if lines:
                output = "\n".join(lines[-LOG_LIMIT:])
                display = f"🚀 Run: `{command}`\n\n```text\n{output}\n```"
                if display != last_text:
                    try:
                        await context.bot.edit_message_text(chat_id=chat_id, message_id=state["last_msg_id"], text=display, parse_mode='Markdown')
                        last_text = display
                    except:
                        pass
            await asyncio.sleep(1.5)

    ui_task = asyncio.create_task(update_ui())

    while True:
        line = await process.stdout.readline()
        if not line: break
        lines.append(line.decode('utf-8').strip())
        if len(lines) > 50: lines.pop(0)

    await process.wait()
    ui_task.cancel()

    status = "✅ Done" if process.returncode == 0 else "❌ Error"
    output = "\n".join(lines[-LOG_LIMIT:])
    await context.bot.edit_message_text(
        chat_id=chat_id, message_id=state["last_msg_id"], 
        text=f"{status}: `{command}`\n\n```text\n{output}\n```", parse_mode='Markdown'
    )

async def handle_file(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ALLOWED_USER_ID: return
    file = await update.message.document.get_file()
    name = update.message.document.file_name
    await file.download_to_drive(name)
    await update.message.reply_text(f"📥 Saved: `{name}`", parse_mode='Markdown')

def main():
    app = Application.builder().token(TOKEN).build()
    app.add_handler(MessageHandler(filters.TEXT & (~filters.COMMAND), run_command))
    app.add_handler(MessageHandler(filters.Document.ALL, handle_file))
    print("Bot is running...")
    app.run_polling()

if __name__ == "__main__":
    main()
EOF

# 5. Lệnh khởi chạy bot
CMD ["python", "bot.py"]


