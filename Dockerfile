```dockerfile
# Sử dụng Ubuntu 24.04 làm nền tảng
FROM ubuntu:24.04

# Chế độ không tương tác
ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt Python và các công cụ hệ thống (Coreutils hỗ trợ stdbuf)
RUN apt-get update && apt-get install -y \
    python3 python3-pip python3-venv \
    curl wget git htop neofetch coreutils \
    build-essential iputils-ping dnsutils net-tools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 2. Thiết lập môi trường ảo Python và cài đặt thư viện Telegram
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir python-telegram-bot --upgrade

# 3. Tạo script bot.py với cơ chế PTY + Hard Kill
RUN cat <<'EOF' > /app/bot.py
import asyncio
import os
import logging
import time
import signal
import pty
import fcntl
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, MessageHandler, filters, ContextTypes, CallbackQueryHandler

# Cấu hình từ Environment Railway
TOKEN = os.getenv("TK")
ID_ENV = os.getenv("ID", "0")
ALLOWED_USER_ID = int(ID_ENV) if ID_ENV.isdigit() else 0
LOG_LIMIT = 10

state = {
    "proc": None,
    "fd": None,
    "last_msg_id": None,
    "current_cmd": "",
    "lines": []
}

logging.basicConfig(level=logging.INFO)

async def run_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not TOKEN or update.effective_user.id != ALLOWED_USER_ID:
        return

    # Nếu đang có lệnh chạy, kiểm tra xem nó còn sống không
    if state["proc"] and state["proc"].returncode is None:
        await update.message.reply_text("⚠️ Lệnh đang chạy. Nhấn 'Dừng lệnh ngay' trước khi gõ lệnh mới.")
        return

    command = update.message.text
    chat_id = update.effective_chat.id
    state["current_cmd"] = command
    state["lines"] = []

    # Xóa log cũ
    if state["last_msg_id"]:
        try: await context.bot.delete_message(chat_id=chat_id, message_id=state["last_msg_id"])
        except: pass

    keyboard = [[InlineKeyboardButton("⛔ Dừng lệnh ngay", callback_data="hard_stop")]]
    markup = InlineKeyboardMarkup(keyboard)

    msg = await update.message.reply_text(f"🚀 **Exec:** `{command}`\n\n`Đang khởi tạo PTY...`", parse_mode='Markdown', reply_markup=markup)
    state["last_msg_id"] = msg.message_id

    # Khởi tạo PTY (Terminal giả lập)
    master_fd, slave_fd = pty.openpty()
    
    # Ép master_fd sang chế độ non-blocking để không bị treo khi đọc
    fl = fcntl.fcntl(master_fd, fcntl.F_GETFL)
    fcntl.fcntl(master_fd, fcntl.F_SETFL, fl | os.O_NONBLOCK)

    # Chạy tiến trình con
    proc = await asyncio.create_subprocess_shell(
        command,
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        preexec_fn=os.setsid # Tạo session mới để kill cả nhóm
    )
    os.close(slave_fd)
    state["proc"] = proc
    state["fd"] = master_fd

    last_update = 0
    start_time = time.time()

    try:
        while proc.returncode is None:
            try:
                # Đọc dữ liệu thô từ terminal
                data = os.read(master_fd, 4096).decode('utf-8', errors='replace')
                if not data: break
                
                # Xử lý từng dòng log
                new_lines = data.splitlines()
                for l in new_lines:
                    clean = l.strip()
                    if clean: state["lines"].append(clean)
                
                if len(state["lines"]) > LOG_LIMIT:
                    state["lines"] = state["lines"][-LOG_LIMIT:]

                now = time.time()
                # Update ngay lập tức ở giây đầu tiên, sau đó 1.2s/lần
                if (now - last_update > 1.2) or (now - start_time < 2.0 and state["lines"]):
                    log_text = "\n".join(state["lines"])
                    await context.bot.edit_message_text(
                        chat_id=chat_id, message_id=state["last_msg_id"],
                        text=f"🚀 **Running:** `{command}`\n\n```text\n{log_text}\n```",
                        parse_mode='Markdown', reply_markup=markup
                    )
                    last_update = now
            except (BlockingIOError, InterruptedError):
                await asyncio.sleep(0.2)
            except Exception:
                break
            
            if proc.returncode is not None: break

    except Exception as e:
        logging.error(f"Error in loop: {e}")

    await proc.wait()
    try: os.close(master_fd)
    except: pass

    # Trạng thái cuối cùng
    status = "✅ Hoàn thành" if proc.returncode == 0 else "🛑 Đã dừng"
    final_output = "\n".join(state["lines"]) if state["lines"] else "Lệnh đã kết thúc."
    try:
        await context.bot.edit_message_text(
            chat_id=chat_id, message_id=state["last_msg_id"],
            text=f"**{status}:** `{command}`\n\n```text\n{final_output}\n```",
            parse_mode='Markdown'
        )
    except: pass
    
    state["proc"] = None
    state["fd"] = None

async def stop_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Xử lý Dừng lệnh bằng cách diệt cả nhóm tiến trình và đóng PTY"""
    query = update.callback_query
    await query.answer()
    
    if state["proc"] and state["proc"].returncode is None:
        try:
            pid = state["proc"].pid
            # 1. Gửi tín hiệu SIGKILL cho toàn bộ nhóm (mạnh nhất)
            os.killpg(os.getpgid(pid), signal.SIGKILL)
            
            # 2. Đóng File Descriptor để ép script thoát (SIGHUP)
            if state["fd"] is not None:
                try: os.close(state["fd"])
                except: pass
            
            # 3. Ép giết trực tiếp đối tượng subprocess
            state["proc"].kill()
            
            await query.edit_message_text(f"🛑 **Đã ép dừng toàn bộ:** `{state['current_cmd']}`", parse_mode='Markdown')
        except Exception as e:
            await query.edit_message_text(f"❌ Lỗi khi dừng: {str(e)}")
        finally:
            state["proc"] = None

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
    app.add_handler(CallbackQueryHandler(stop_callback, pattern="hard_stop"))
    print(f"Bot SSH Railway (PTY Mode) Ready cho ID: {ALLOWED_USER_ID}")
    app.run_polling()

if __name__ == "__main__":
    main()
EOF

# 4. Chạy bot ở chế độ Unbuffered
CMD ["python3", "-u", "bot.py"]

```
