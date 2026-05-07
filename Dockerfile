# Sử dụng Ubuntu 24.04
FROM ubuntu:24.04

# Chế độ không tương tác
ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt Python và các công cụ hệ thống cần thiết
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

# 3. Tạo file bot.py (Sửa lỗi NameError và tối ưu Live Log)
RUN cat <<'EOF' > /app/bot.py
import asyncio
import os
import logging
import time
import signal
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, MessageHandler, filters, ContextTypes, CallbackQueryHandler

# Lấy biến môi trường từ Railway
TOKEN = os.getenv("TK")
try:
    ID_VAL = os.getenv("ID", "0")
    ALLOWED_USER_ID = int(ID_VAL) if ID_VAL.isdigit() else 0
except:
    ALLOWED_USER_ID = 0

LOG_LIMIT = 10

state = {
    "process": None,
    "last_msg_id": None,
    "current_cmd": "",
    "lines": []
}

logging.basicConfig(level=logging.INFO)

async def run_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not TOKEN or update.effective_user.id != ALLOWED_USER_ID:
        return

    if state["process"] and state["process"].returncode is None:
        await update.message.reply_text("⚠️ Lệnh cũ chưa dừng. Nhấn nút 'Dừng' bên dưới log cũ.")
        return

    cmd = update.message.text
    chat_id = update.effective_chat.id
    state["current_cmd"] = cmd
    state["lines"] = []

    # Xóa log cũ để sạch màn hình
    if state["last_msg_id"]:
        try: await context.bot.delete_message(chat_id=chat_id, message_id=state["last_msg_id"])
        except: pass

    # Nút dừng lệnh (callback_data)
    keyboard = [[InlineKeyboardButton("⛔ Dừng lệnh", callback_data="stop_process")]]
    markup = InlineKeyboardMarkup(keyboard)

    # Gửi tin nhắn khởi tạo
    msg = await update.message.reply_text(
        f"🚀 **Exec:** `{cmd}`\n\n`Đang khởi động...`", 
        parse_mode='Markdown', 
        reply_markup=markup
    )
    state["last_msg_id"] = msg.message_id

    # Khởi chạy lệnh với stdbuf để xuất log ngay lập tức
    state["process"] = await asyncio.create_subprocess_shell(
        f"stdbuf -i0 -oL -eL {cmd}",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
        preexec_fn=os.setsid
    )

    last_update = 0
    
    try:
        while True:
            line = await state["process"].stdout.readline()
            if not line: break
            
            text = line.decode('utf-8', errors='replace').strip()
            if text:
                state["lines"].append(text)
                if len(state["lines"]) > LOG_LIMIT: state["lines"].pop(0)

                now = time.time()
                # Cập nhật log mỗi 1.2s
                if now - last_update > 1.2:
                    log_content = "\n".join(state["lines"])
                    try:
                        await context.bot.edit_message_text(
                            chat_id=chat_id, 
                            message_id=state["last_msg_id"],
                            text=f"🚀 **Running:** `{cmd}`\n\n```text\n{log_content}\n```",
                            parse_mode='Markdown', 
                            reply_markup=markup
                        )
                        last_update = now
                    except: pass
    except Exception as e:
        logging.error(f"Error: {e}")

    await state["process"].wait()
    
    # Kết thúc lệnh
    final_log = "\n".join(state["lines"]) if state["lines"] else "No output."
    status = "✅ Done" if state["process"].returncode == 0 else "🛑 Stopped"
    try:
        await context.bot.edit_message_text(
            chat_id=chat_id, 
            message_id=state["last_msg_id"],
            text=f"**{status}:** `{cmd}`\n\n```text\n{final_log}\n```",
            parse_mode='Markdown'
        )
    except: pass
    state["process"] = None

async def stop_process(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Xử lý nút dừng"""
    query = update.callback_query
    await query.answer()
    if state["process"] and state["process"].returncode is None:
        try:
            os.killpg(os.getpgid(state["process"].pid), signal.SIGTERM)
            await query.edit_message_text(f"🛑 **Đã dừng:** `{state['current_cmd']}`", parse_mode='Markdown')
        except: pass

async def handle_document(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Xử lý tải file lên"""
    if update.effective_user.id != ALLOWED_USER_ID: return
    f = await update.message.document.get_file()
    name = update.message.document.file_name
    await f.download_to_drive(name)
    await update.message.reply_text(f"📥 Đã lưu file: `{name}`")

def main():
    if not TOKEN:
        print("LỖI: Thiếu biến TK")
        return
    
    app = Application.builder().token(TOKEN).build()
    
    # Handlers
    app.add_handler(MessageHandler(filters.TEXT & (~filters.COMMAND), run_command))
    app.add_handler(MessageHandler(filters.Document.ALL, handle_document))
    app.add_handler(CallbackQueryHandler(stop_process, pattern="stop_process"))
    
    print(f"Bot SSH Railway đang chạy cho ID: {ALLOWED_USER_ID}")
    app.run_polling()

if __name__ == "__main__":
    main()
EOF

# 4. Chạy bot ở chế độ Unbuffered
CMD ["python3", "-u", "bot.py"]
