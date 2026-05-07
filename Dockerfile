# Sử dụng Ubuntu 24.04
FROM ubuntu:24.04

# Chế độ không tương tác
ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt Python và các công cụ cần thiết
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

# 3. Tạo script bot.py sử dụng PTY để ép Log ra ngay lập tức
RUN cat <<'EOF' > /app/bot.py
import asyncio
import os
import logging
import time
import signal
import pty
import tty
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, MessageHandler, filters, ContextTypes, CallbackQueryHandler

# Cấu hình từ Environment Railway
TOKEN = os.getenv("TK")
ID_ENV = os.getenv("ID", "0")
ALLOWED_USER_ID = int(ID_ENV) if ID_ENV.isdigit() else 0
LOG_LIMIT = 10

state = {
    "child_pid": None,
    "fd": None,
    "last_msg_id": None,
    "current_cmd": "",
    "lines": [],
    "task": None
}

logging.basicConfig(level=logging.INFO)

async def run_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not TOKEN or update.effective_user.id != ALLOWED_USER_ID:
        return

    if state["child_pid"] is not None:
        await update.message.reply_text("⚠️ Lệnh đang chạy! Nhấn nút 'Dừng' bên dưới.")
        return

    cmd = update.message.text
    chat_id = update.effective_chat.id
    state["current_cmd"] = cmd
    state["lines"] = []

    # Dọn dẹp log cũ
    if state["last_msg_id"]:
        try: await context.bot.delete_message(chat_id=chat_id, message_id=state["last_msg_id"])
        except: pass

    keyboard = [[InlineKeyboardButton("⛔ Dừng lệnh ngay", callback_data="stop_now")]]
    markup = InlineKeyboardMarkup(keyboard)

    msg = await update.message.reply_text(f"🚀 **Exec:** `{cmd}`\n\n`Đang khởi tạo terminal...`", parse_mode='Markdown', reply_markup=markup)
    state["last_msg_id"] = msg.message_id

    # SỬ DỤNG PTY ĐỂ ÉP LOG RA NGAY LẬP TỨC
    master_fd, slave_fd = pty.openpty()
    
    # Khởi tạo tiến trình con
    proc = await asyncio.create_subprocess_shell(
        cmd,
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        preexec_fn=os.setsid
    )
    os.close(slave_fd)
    state["child_pid"] = proc.pid
    state["fd"] = master_fd

    last_update = 0
    start_time = time.time()

    try:
        while proc.returncode is None:
            try:
                # Đọc dữ liệu từ PTY (không chờ dòng mới, có byte nào lấy byte đó)
                data = os.read(master_fd, 1024).decode('utf-8', errors='replace')
                if not data: break
                
                for line in data.splitlines():
                    clean_line = line.strip()
                    if clean_line:
                        state["lines"].append(clean_line)
                
                if len(state["lines"]) > LOG_LIMIT:
                    state["lines"] = state["lines"][-LOG_LIMIT:]

                now = time.time()
                # Cập nhật log: Ưu tiên phát đầu tiên hoặc sau mỗi 1.2s
                if now - last_update > 1.2 or (now - start_time < 2 and len(state["lines"]) > 0):
                    log_content = "\n".join(state["lines"])
                    await context.bot.edit_message_text(
                        chat_id=chat_id, message_id=state["last_msg_id"],
                        text=f"🚀 **Running:** `{cmd}`\n\n```text\n{log_content}\n```",
                        parse_mode='Markdown', reply_markup=markup
                    )
                    last_update = now
            except BlockingIOError:
                await asyncio.sleep(0.1)
            except Exception:
                break
    except Exception as e:
        logging.error(f"Lỗi: {e}")

    await proc.wait()
    os.close(master_fd)

    final_log = "\n".join(state["lines"]) if state["lines"] else "Lệnh đã kết thúc."
    status = "✅ Hoàn thành" if proc.returncode == 0 else "🛑 Đã dừng"
    try:
        await context.bot.edit_message_text(
            chat_id=chat_id, message_id=state["last_msg_id"],
            text=f"**{status}:** `{cmd}`\n\n```text\n{final_log}\n```",
            parse_mode='Markdown'
        )
    except: pass
    
    state["child_pid"] = None
    state["fd"] = None

async def stop_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    
    if state["child_pid"]:
        try:
            # Gửi tín hiệu KILL mạnh nhất để dừng ngay lập tức
            os.killpg(os.getpgid(state["child_pid"]), signal.SIGKILL)
            await query.edit_message_text(f"🛑 **Đã ép dừng:** `{state['current_cmd']}`", parse_mode='Markdown')
        except Exception as e:
            await query.edit_message_text(f"❌ Lỗi khi dừng: {str(e)}")
        finally:
            state["child_pid"] = None

async def handle_document(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ALLOWED_USER_ID: return
    f = await update.message.document.get_file()
    name = update.message.document.file_name
    await f.download_to_drive(name)
    await update.message.reply_text(f"📥 Đã nhận file: `{name}`")

def main():
    if not TOKEN: return
    app = Application.builder().token(TOKEN).build()
    app.add_handler(MessageHandler(filters.TEXT & (~filters.COMMAND), run_command))
    app.add_handler(MessageHandler(filters.Document.ALL, handle_document))
    app.add_handler(CallbackQueryHandler(stop_callback, pattern="stop_now"))
    print(f"Bot SSH PTY Mode đang chạy cho ID: {ALLOWED_USER_ID}")
    app.run_polling()

if __name__ == "__main__":
    main()
EOF

# 4. Chạy bot
CMD ["python3", "-u", "bot.py"]
