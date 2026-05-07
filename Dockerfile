# Sử dụng Ubuntu 24.04 làm nền tảng
FROM ubuntu:24.04

# Ngăn các câu hỏi tương tác trong quá trình build
ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt Python, các công cụ hệ thống và công cụ mạng
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y \
    python3 python3-pip python3-venv \
    curl wget git htop neofetch coreutils \
    build-essential iputils-ping dnsutils net-tools vim \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 2. Thiết lập môi trường ảo Python và cài đặt thư viện Telegram
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir python-telegram-bot --upgrade

# 3. Tạo script điều khiển (bot.py) tích hợp Live Log và Stop Command
RUN cat <<'EOF' > /app/bot.py
import asyncio
import os
import logging
import time
import signal
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, MessageHandler, filters, ContextTypes, CallbackQueryHandler

# Lấy biến môi trường từ Railway Variables
TOKEN = os.getenv("TK")
try:
    ALLOWED_USER_ID = int(os.getenv("ID")) if os.getenv("ID") else 0
except:
    ALLOWED_USER_ID = 0

LOG_LIMIT = 10

# Trạng thái quản lý tiến trình
state = {
    "process": None,
    "last_msg_id": None,
    "current_command": "",
    "lines": []
}

logging.basicConfig(level=logging.INFO)

async def run_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Thực thi lệnh shell và cập nhật log trực tiếp"""
    if not TOKEN or update.effective_user.id != ALLOWED_USER_ID:
        return

    # Kiểm tra nếu đang có lệnh chạy
    if state["process"] and state["process"].returncode is None:
        await update.message.reply_text("⚠️ Một lệnh khác đang chạy. Nhấn 'Dừng' trước khi chạy lệnh mới.")
        return

    command = update.message.text
    chat_id = update.effective_chat.id
    state["current_command"] = command
    state["lines"] = []

    # Xóa log cũ để làm sạch màn hình
    if state["last_msg_id"]:
        try: await context.bot.delete_message(chat_id=chat_id, message_id=state["last_msg_id"])
        except: pass

    # Nút bấm để dừng lệnh
    keyboard = [[InlineKeyboardButton("⛔ Dừng lệnh", callback_query_data="stop_cmd")]]
    reply_markup = InlineKeyboardMarkup(keyboard)

    # Tin nhắn chờ ban đầu
    log_msg = await update.message.reply_text(
        f"🚀 **Đang chạy:** `{command}`\n\n`Đang khởi động...`",
        parse_mode='Markdown',
        reply_markup=reply_markup
    )
    state["last_msg_id"] = log_msg.message_id

    # Sử dụng stdbuf để đẩy log ra ngay lập tức, không đợi đầy bộ đệm
    state["process"] = await asyncio.create_subprocess_shell(
        f"stdbuf -i0 -oL -eL {command}",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
        preexec_fn=os.setsid # Cho phép kill cả nhóm tiến trình con
    )

    last_update_time = 0
    start_cleared = False # Đánh dấu đã xóa chữ "Đang khởi động" chưa
    
    try:
        while True:
            line_bytes = await state["process"].stdout.readline()
            if not line_bytes:
                break
            
            line_text = line_bytes.decode('utf-8', errors='replace').strip()
            if line_text:
                state["lines"].append(line_text)
                if len(state["lines"]) > LOG_LIMIT:
                    state["lines"].pop(0)

                now = time.time()
                # Cập nhật log mỗi 1.2s để tuân thủ giới hạn của Telegram
                if now - last_update_time > 1.2:
                    output = "\n".join(state["lines"])
                    # Cập nhật nội dung log, ghi đè chữ khởi động
                    text = f"🚀 **Running:** `{command}`\n\n```text\n{output}\n```"
                    try:
                        await context.bot.edit_message_text(
                            chat_id=chat_id,
                            message_id=state["last_msg_id"],
                            text=text,
                            parse_mode='Markdown',
                            reply_markup=reply_markup
                        )
                        last_update_time = now
                        start_cleared = True
                    except: pass
    except Exception as e:
        logging.error(f"Lỗi vòng lặp: {e}")

    await state["process"].wait()
    
    # Thông báo kết quả cuối cùng
    status = "✅ Hoàn thành" if state["process"].returncode == 0 else "🛑 Đã dừng"
    final_output = "\n".join(state["lines"]) if state["lines"] else "Kết thúc, không có output."
    try:
        await context.bot.edit_message_text(
            chat_id=chat_id,
            message_id=state["last_msg_id"],
            text=f"**{status}:** `{command}`\n\n```text\n{final_output}\n```",
            parse_mode='Markdown'
        )
    except: pass
    state["process"] = None

async def stop_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Xử lý nút dừng lệnh"""
    query = update.callback_query
    await query.answer()
    if state["process"] and state["process"].returncode is None:
        try:
            # Gửi tín hiệu dừng tới toàn bộ tiến trình
            os.killpg(os.getpgid(state["process"].pid), signal.SIGTERM)
            await query.edit_message_text(f"🛑 **Đang dừng:** `{state['current_command']}`...", parse_mode='Markdown')
        except: pass

async def handle_document(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Tải file từ Telegram trực tiếp lên Railway"""
    if update.effective_user.id != ALLOWED_USER_ID: return
    file = await update.message.document.get_file()
    name = update.message.document.file_name
    await file.download_to_drive(name)
    await update.message.reply_text(f"📥 Đã lưu file: `{name}`")

def main():
    if not TOKEN:
        print("LỖI: Chưa cấu hình biến 'TK' trên Railway!")
        return
    
    app = Application.builder().token(TOKEN).build()
    app.add_handler(MessageHandler(filters.TEXT & (~filters.COMMAND), run_command))
    app.add_handler(MessageHandler(filters.Document.ALL, handle_document))
    app.add_handler(CallbackQueryHandler(stop_callback, pattern="stop_cmd"))
    
    print(f"Bot khởi động thành công cho ID: {ALLOWED_USER_ID}")
    app.run_polling()

if __name__ == "__main__":
    main()
EOF

# 4. Chạy Python ở chế độ Unbuffered để log hiện ra ngay
CMD ["python3", "-u", "bot.py"]
