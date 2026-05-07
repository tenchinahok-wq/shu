
# Sử dụng Ubuntu 24.04
FROM ubuntu:24.04

# Ngăn các câu hỏi tương tác
ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt Python và các công cụ hệ thống cần thiết
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y \
    python3 python3-pip python3-venv \
    curl wget git htop neofetch coreutils \
    build-essential iputils-ping dnsutils net-tools vim \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 2. Cài đặt thư viện Telegram
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir python-telegram-bot --upgrade

# 3. Tạo file bot.py trực tiếp (Cập nhật Live Log cho script 1 dòng/giây)
RUN cat <<'EOF' > /app/bot.py
import asyncio
import os
import logging
import time
from telegram import Update
from telegram.ext import Application, MessageHandler, filters, ContextTypes

# --- CẤU HÌNH ---
TOKEN = "8190267925:AAHHdE2YuYWd9PfPXIILlzP-KA0SmynGhsc"
ALLOWED_USER_ID = 6974873344 # Thay bằng ID của bạn
LOG_LIMIT = 10 

# Lưu trữ trạng thái tin nhắn
state = {"last_msg_id": None}

logging.basicConfig(level=logging.INFO)

async def run_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ALLOWED_USER_ID:
        return

    command = update.message.text
    chat_id = update.effective_chat.id
    
    # Xoá tin nhắn cũ nếu có để tránh rối
    if state["last_msg_id"]:
        try:
            await context.bot.delete_message(chat_id=chat_id, message_id=state["last_msg_id"])
        except:
            pass

    # Gửi tin nhắn khởi tạo
    log_msg = await update.message.reply_text(f"🚀 **Đang chạy:** `{command}`\n\n`Đang khởi động...`", parse_mode='Markdown')
    state["last_msg_id"] = log_msg.message_id

    # SỬ DỤNG stdbuf ĐỂ ÉP LOG RA NGAY LẬP TỨC (Rất quan trọng cho script 1s/dòng)
    process = await asyncio.create_subprocess_shell(
        f"stdbuf -i0 -oL -eL {command}",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT
    )

    lines = []
    last_update_time = 0
    # Telegram cho phép sửa tin nhắn tối đa 1 lần/giây
    MIN_UPDATE_INTERVAL = 1.1 

    async def update_telegram():
        nonlocal last_update_time
        now = time.time()
        # Chỉ cập nhật nếu có dòng mới và đủ thời gian chờ
        if lines and (now - last_update_time >= MIN_UPDATE_INTERVAL):
            output = "\n".join(lines[-LOG_LIMIT:])
            text = f"🚀 **Running:** `{command}`\n\n```text\n{output}\n```"
            try:
                await context.bot.edit_message_text(
                    chat_id=chat_id, 
                    message_id=state["last_msg_id"], 
                    text=text, 
                    parse_mode='Markdown'
                )
                last_update_time = now
            except Exception as e:
                # Bỏ qua lỗi nếu nội dung không đổi
                pass

    # Vòng lặp đọc output theo thời gian thực
    while True:
        line_bytes = await process.stdout.readline()
        if not line_bytes:
            break
        
        line_text = line_bytes.decode('utf-8', errors='replace').strip()
        if line_text:
            lines.append(line_text)
            if len(lines) > 50: # Giữ tối đa 50 dòng trong bộ nhớ để tiết kiệm RAM
                lines.pop(0)
            
            # Thử cập nhật tin nhắn ngay khi có dòng mới
            await update_telegram()

    await process.wait()

    # Thông báo hoàn thành và hiển thị log cuối cùng
    status = "✅ **Hoàn thành**" if process.returncode == 0 else "❌ **Lỗi**"
    final_output = "\n".join(lines[-LOG_LIMIT:]) if lines else "Không có output."
    try:
        await context.bot.edit_message_text(
            chat_id=chat_id, 
            message_id=state["last_msg_id"], 
            text=f"{status}: `{command}`\n\n```text\n{final_output}\n```", 
            parse_mode='Markdown'
        )
    except:
        pass

async def handle_file(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Lưu file gửi từ điện thoại vào server"""
    if update.effective_user.id != ALLOWED_USER_ID: return
    file = await update.message.document.get_file()
    name = update.message.document.file_name
    await file.download_to_drive(name)
    await update.message.reply_text(f"📥 **Đã lưu file:** `{name}`", parse_mode='Markdown')

def main():
    app = Application.builder().token(TOKEN).build()
    # Chạy mọi lệnh text
    app.add_handler(MessageHandler(filters.TEXT & (~filters.COMMAND), run_command))
    # Nhận file trực tiếp
    app.add_handler(MessageHandler(filters.Document.ALL, handle_file))
    print("Bot SSH Live Log đang hoạt động...")
    app.run_polling()

if __name__ == "__main__":
    main()
EOF

# 5. Chạy Python ở chế độ Unbuffered
CMD ["python3", "-u", "bot.py"]


