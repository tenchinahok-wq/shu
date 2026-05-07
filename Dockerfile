# Sử dụng Ubuntu 24.04
FROM ubuntu:24.04

# Chế độ không tương tác
ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt Python và các công cụ hệ thống
RUN apt-get update && apt-get install -y \
    python3 python3-pip python3-venv \
    curl wget git htop neofetch coreutils \
    build-essential iputils-ping dnsutils net-tools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 2. Cài đặt thư viện Telegram
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir python-telegram-bot --upgrade

# 3. Tạo script bot.py (Cơ chế đa nhiệm + Kill tuyệt đối)
RUN cat <<'EOF' > /app/bot.py
import asyncio
import os
import logging
import time
import signal
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, MessageHandler, filters, ContextTypes, CallbackQueryHandler

# Cấu hình từ Environment Railway
TOKEN = os.getenv("TK")
ID_ENV = os.getenv("ID", "0")
ALLOWED_USER_ID = int(ID_ENV) if ID_ENV.isdigit() else 0
LOG_LIMIT = 10

# Quản lý tiến trình theo Chat ID (Cho phép đa nhiệm)
active_tasks = {}

logging.basicConfig(level=logging.INFO)

async def kill_process(chat_id):
    """Tiêu diệt tiến trình đang chạy của một chat cụ thể"""
    if chat_id in active_tasks:
        task_info = active_tasks[chat_id]
        proc = task_info.get("proc")
        if proc and proc.returncode is None:
            try:
                # Giết cả nhóm tiến trình (Nuclear Kill)
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                proc.kill()
            except:
                pass
        return True
    return False

async def run_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    if not TOKEN or update.effective_user.id != ALLOWED_USER_ID:
        return

    command = update.message.text

    # Nếu đang có lệnh chạy, tự động dừng để chạy lệnh mới (Phản hồi tức thì)
    if chat_id in active_tasks:
        await kill_process(chat_id)
        # Đợi một chút để hệ thống giải phóng tài nguyên
        await asyncio.sleep(0.5)

    # Nút bấm dừng lệnh
    keyboard = [[InlineKeyboardButton("⛔ DỪNG LỆNH NGAY LẬP TỨC", callback_data=f"stop_{chat_id}")]]
    markup = InlineKeyboardMarkup(keyboard)

    # Gửi tin nhắn khởi tạo
    msg = await update.message.reply_text(
        f"🚀 **Exec:** `{command}`\n\n`Đang chuẩn bị...`",
        parse_mode='Markdown',
        reply_markup=markup
    )
    
    # Khởi chạy lệnh với cơ chế exec để dễ kill
    # stdbuf -i0 -oL -eL đảm bảo log không bị đệm
    proc = await asyncio.create_subprocess_shell(
        f"exec stdbuf -i0 -oL -eL {command}",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
        preexec_fn=os.setsid
    )

    active_tasks[chat_id] = {
        "proc": proc,
        "msg_id": msg.message_id,
        "command": command,
        "lines": []
    }

    last_update = 0
    
    try:
        while True:
            line_bytes = await proc.stdout.readline()
            if not line_bytes:
                break
            
            text = line_bytes.decode('utf-8', errors='replace').strip()
            if text:
                active_tasks[chat_id]["lines"].append(text)
                if len(active_tasks[chat_id]["lines"]) > LOG_LIMIT:
                    active_tasks[chat_id]["lines"].pop(0)

                now = time.time()
                # Cập nhật log: Phóng ngay lập tức dòng đầu, sau đó 1.2s/lần
                if now - last_update > 1.2 or len(active_tasks[chat_id]["lines"]) == 1:
                    log_content = "\n".join(active_tasks[chat_id]["lines"])
                    try:
                        await context.bot.edit_message_text(
                            chat_id=chat_id,
                            message_id=msg.message_id,
                            text=f"🚀 **Running:** `{command}`\n\n```text\n{log_content}\n```",
                            parse_mode='Markdown',
                            reply_markup=markup
                        )
                        last_update = now
                    except:
                        pass
    except Exception as e:
        logging.error(f"Error: {e}")

    await proc.wait()
    
    # Kết thúc
    final_lines = active_tasks[chat_id]["lines"]
    final_log = "\n".join(final_lines) if final_lines else "Lệnh đã dừng hoặc không có output."
    status = "✅ Hoàn thành" if proc.returncode == 0 else "🛑 Đã dừng"
    
    try:
        await context.bot.edit_message_text(
            chat_id=chat_id,
            message_id=msg.message_id,
            text=f"**{status}:** `{command}`\n\n```text\n{final_log}\n```",
            parse_mode='Markdown'
        )
    except:
        pass
    
    # Dọn dẹp task
    if chat_id in active_tasks and active_tasks[chat_id]["proc"] == proc:
        del active_tasks[chat_id]

async def stop_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    chat_id = update.effective_chat.id
    await query.answer()
    
    if await kill_process(chat_id):
        try:
            await query.edit_message_text("🛑 **Lệnh đã được ép dừng cưỡng bức.**", parse_mode='Markdown')
        except:
            pass

async def handle_document(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ALLOWED_USER_ID: return
    f = await update.message.document.get_file()
    name = update.message.document.file_name
    await f.download_to_drive(name)
    await update.message.reply_text(f"📥 Đã lưu file: `{name}`")

def main():
    if not TOKEN: return
    app = Application.builder().token(TOKEN).build()
    app.add_handler(MessageHandler(filters.TEXT & (~filters.COMMAND), run_command))
    app.add_handler(MessageHandler(filters.Document.ALL, handle_document))
    app.add_handler(CallbackQueryHandler(stop_callback, pattern="^stop_"))
    print(f"Bot SSH Railway Mode: Đa nhiệm & Hard Kill đang chạy...")
    app.run_polling()

if __name__ == "__main__":
    main()
EOF

# 4. Chạy bot ở chế độ Unbuffered
CMD ["python3", "-u", "bot.py"]
