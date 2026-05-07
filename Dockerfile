
# Sử dụng Ubuntu 24.04
FROM ubuntu:24.04

# Ngăn các câu hỏi tương tác
ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt Python, các công cụ hệ thống và các gói mạng
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

# 3. Cấu hình biến môi trường mặc định (Có thể ghi đè khi run docker)
ENV TK=""
ENV ID=""
ENV PYTHONUNBUFFERED=1

# 4. Tạo file bot.py hỗ trợ Live Log và Nút Dừng
RUN cat <<'EOF' > /app/bot.py
import asyncio
import os
import logging
import time
import signal
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, MessageHandler, filters, ContextTypes, CallbackQueryHandler

# Lấy cấu hình từ biến môi trường
TOKEN = os.getenv("TK")
ALLOWED_USER_ID = int(os.getenv("ID")) if os.getenv("ID") else 0
LOG_LIMIT = 10

# Quản lý tiến trình đang chạy
state = {
    "process": None,
    "last_msg_id": None,
    "current_command": ""
}

logging.basicConfig(level=logging.INFO)

async def run_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not TOKEN or update.effective_user.id != ALLOWED_USER_ID:
        return

    # Nếu đang có lệnh chạy, yêu cầu dừng trước
    if state["process"] and state["process"].returncode is None:
        await update.message.reply_text("⚠️ Có lệnh đang chạy. Hãy nhấn 'Dừng' trước khi chạy lệnh mới.")
        return

    command = update.message.text
    chat_id = update.effective_chat.id
    state["current_command"] = command

    # Xóa log cũ
    if state["last_msg_id"]:
        try: await context.bot.delete_message(chat_id=chat_id, message_id=state["last_msg_id"])
        except: pass

    # Tạo nút Dừng
    keyboard = [[InlineKeyboardButton("⛔ Dừng lệnh", callback_query_data="stop_cmd")]]
    reply_markup = InlineKeyboardMarkup(keyboard)

    log_msg = await update.message.reply_text(
        f"🚀 **Đang chạy:** `{command}`\n\n`Đang khởi động...`", 
        parse_mode='Markdown',
        reply_markup=reply_markup
    )
    state["last_msg_id"] = log_msg.message_id

    # Ép lệnh ra log ngay lập tức bằng stdbuf
    state["process"] = await asyncio.create_subprocess_shell(
        f"stdbuf -i0 -oL -eL {command}",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
        preexec_fn=os.setsid # Để có thể kill cả nhóm tiến trình
    )

    lines = []
    last_update = 0

    try:
        while True:
            line_bytes = await state["process"].stdout.readline()
            if not line_bytes:
                break
            
            line_text = line_bytes.decode('utf-8', errors='replace').strip()
            if line_text:
                lines.append(line_text)
                if len(lines) > LOG_LIMIT: lines.pop(0)

            # Cập nhật log mỗi 1.2 giây (tránh rate limit Telegram)
            now = time.time()
            if now - last_update > 1.2:
                output = "\n".join(lines)
                display = f"🚀 **Running:** `{command}`\n\n```text\n{output}\n```"
                try:
                    await context.bot.edit_message_text(
                        chat_id=chat_id, message_id=state["last_msg_id"],
                        text=display, parse_mode='Markdown', reply_markup=reply_markup
                    )
                    last_update = now
                except: pass
    except Exception as e:
        logging.error(f"Error: {e}")

    await state["process"].wait()
    
    # Kết thúc
    status = "✅ Hoàn thành" if state["process"].returncode == 0 else "🛑 Đã dừng/Lỗi"
    final_output = "\n".join(lines) if lines else "No output."
    try:
        await context.bot.edit_message_text(
            chat_id=chat_id, message_id=state["last_msg_id"],
            text=f"**{status}:** `{command}`\n\n```text\n{final_output}\n```", 
            parse_mode='Markdown'
        )
    except: pass
    state["process"] = None

async def stop_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Xử lý khi nhấn nút Dừng"""
    query = update.callback_query
    await query.answer()
    
    if state["process"] and state["process"].returncode is None:
        try:
            # Gửi tín hiệu dừng tới toàn bộ nhóm tiến trình
            os.killpg(os.getpgid(state["process"].pid), signal.SIGTERM)
            await query.edit_message_text(f"🛑 **Đang dừng lệnh:** `{state['current_command']}`...", parse_mode='Markdown')
        except Exception as e:
            await query.edit_message_text(f"❌ Không thể dừng: {str(e)}")

async def handle_file(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ALLOWED_USER_ID: return
    file = await update.message.document.get_file()
    name = update.message.document.file_name
    await file.download_to_drive(name)
    await update.message.reply_text(f"📥 Đã lưu file: `{name}`")

def main():
    if not TOKEN:
        print("LỖI: Chưa có biến TK (Token)!")
        return
    app = Application.builder().token(TOKEN).build()
    app.add_handler(MessageHandler(filters.TEXT & (~filters.COMMAND), run_command))
    app.add_handler(MessageHandler(filters.Document.ALL, handle_file))
    app.add_handler(CallbackQueryHandler(stop_callback, pattern="stop_cmd"))
    print(f"Bot đang chạy cho ID: {ALLOWED_USER_ID}")
    app.run_polling()

if __name__ == "__main__":
    main()
EOF

# 5. Chạy bot
CMD ["python3", "-u", "bot.py"]
