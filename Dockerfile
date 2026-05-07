# Sử dụng Ubuntu 24.04 làm gốc
FROM ubuntu:24.04

# Chế độ không tương tác để cài đặt nhanh
ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt Python và các công cụ hệ thống cần thiết (Cực nhanh)
RUN apt-get update && apt-get install -y \
    python3 python3-pip python3-venv \
    curl wget git htop neofetch coreutils \
    build-essential iputils-ping dnsutils net-tools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 2. Cài đặt thư viện Telegram (v21.0+)
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir python-telegram-bot --upgrade

# 3. Tạo file bot.py trực tiếp (Tối ưu Live Log & Stop Button)
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
try:
    ID_STR = os.getenv("ID", "0")
    ALLOWED_USER_ID = int(ID_STR) if ID_STR.isdigit() else 0
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
        await update.message.reply_text("⚠️ Lệnh cũ đang chạy. Hãy nhấn 'Dừng'!")
        return

    cmd = update.message.text
    chat_id = update.effective_chat.id
    state["current_cmd"] = cmd
    state["lines"] = []

    # Xóa log cũ
    if state["last_msg_id"]:
        try: await context.bot.delete_message(chat_id=chat_id, message_id=state["last_msg_id"])
        except: pass

    # Nút dừng lệnh (callback_data thay vì callback_query_data)
    keyboard = [[InlineKeyboardButton("⛔ Dừng lệnh", callback_data="stop")]]
    markup = InlineKeyboardMarkup(keyboard)

    msg = await update.message.reply_text(f"🚀 **Exec:** `{cmd}`\n\n`Đang khởi tạo...`", parse_mode='Markdown', reply_markup=markup)
    state["last_msg_id"] = msg.message_id

    # Chạy lệnh với stdbuf để log chảy ra ngay lập tức
    state["process"] = await asyncio.create_subprocess_shell(
        f"stdbuf -i0 -oL -eL {cmd}",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
        preexec_fn=os.setsid
    )

    last_up = 0
    while True:
        line = await state["process"].stdout.readline()
        if not line: break
        
        text = line.decode('utf-8', errors='replace').strip()
        if text:
            state["lines"].append(text)
            if len(state["lines"]) > LOG_LIMIT: state["lines"].pop(0)

            # Cập nhật mỗi 1.2s để tránh bị Telegram chặn
            now = time.time()
            if now - last_up > 1.2:
                log_content = "\n".join(state["lines"])
                try:
                    await context.bot.edit_message_text(
                        chat_id=chat_id, message_id=state["last_msg_id"],
                        text=f"🚀 **Running:** `{cmd}`\n\n```text\n{log_content}\n```",
                        parse_mode='Markdown', reply_markup=markup
                    )
                    last_up = now
                except: pass

    await state["process"].wait()
    
    # Kết thúc
    final_log = "\n".join(state["lines"]) if state["lines"] else "No output."
    status = "✅ Done" if state["process"].returncode == 0 else "🛑 Stopped"
    try:
        await context.bot.edit_message_text(
            chat_id=chat_id, message_id=state["last_msg_id"],
            text=f"**{status}:** `{cmd}`\n\n```text\n{final_log}\n```",
            parse_mode='Markdown'
        )
    except: pass
    state["process"] = None

async def stop_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    if state["process"] and state["process"].returncode is None:
        try:
            os.killpg(os.getpgid(state["process"].pid), signal.SIGTERM)
            await query.edit_message_text(f"🛑 **Đã dừng:** `{state['current_cmd']}`", parse_mode='Markdown')
        except: pass

async def handle_file(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ALLOWED_USER_ID: return
    f = await update.message.document.get_file()
    name = update.message.document.file_name
    await f.download_to_drive(name)
    await update.message.reply_text(f"📥 Đã lưu: `{name}`")

def main():
    if not TOKEN: return
    app = Application.builder().token(TOKEN).build()
    app.add_handler(MessageHandler(filters.TEXT & (~filters.COMMAND), run_command))
    app.add_handler(MessageHandler(filters.Document.ALL, handle_document))
    app.add_handler(CallbackQueryHandler(stop_cmd, pattern="stop"))
    print(f"Bot SSH Ubuntu đang chạy cho ID: {ALLOWED_USER_ID}")
    app.run_polling()

if __name__ == "__main__":
    main()
EOF

# 4. Lệnh chạy (Sử dụng python3 -u để không bị đệm log)
CMD ["python3", "-u", "bot.py"]
