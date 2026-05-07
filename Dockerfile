# Sử dụng Ubuntu 24.04 để có đầy đủ công cụ hệ thống
FROM ubuntu:24.04

# Chế độ không tương tác
ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt Node.js, Python (cho một số script) và các công cụ network
RUN apt-get update && apt-get install -y \
    curl wget git htop neofetch coreutils \
    build-essential iputils-ping dnsutils net-tools vim \
    gnupg && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 2. Khởi tạo dự án Node.js và cài đặt Telegraf
RUN npm init -y && npm install telegraf

# 3. Tạo file index.js (Logic đa nhiệm, Live Log, Hard Kill)
RUN cat <<'EOF' > index.js
const { Telegraf, Markup } = require('telegraf');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const bot = new Telegraf(process.env.TK);
const ALLOWED_ID = process.env.ID;
const LOG_LIMIT = 10;

// Lưu trữ các tiến trình đang chạy: msgId -> { proc, lines, command, lastUpdate }
const activeTasks = new Map();

// Hàm cập nhật log lên Telegram
async function sendUpdate(ctx, msgId, command, lines, isFinal = false) {
    const task = activeTasks.get(msgId);
    if (!task && !isFinal) return;

    const now = Date.now();
    // Giới hạn 1.2 giây/lần cập nhật để tránh rate limit của Telegram
    if (!isFinal && task.lastUpdate && (now - task.lastUpdate < 1200)) return;

    const output = lines.slice(-LOG_LIMIT).join('\n') || 'Đang chờ dữ liệu...';
    const status = isFinal ? '✅ Hoàn thành' : '🚀 Running';
    const text = `**${status}:** \`${command}\`\n\n\`\`\`text\n${output}\n\`\`\``;

    try {
        await ctx.telegram.editMessageText(
            ctx.chat.id,
            msgId,
            null,
            text,
            {
                parse_mode: 'Markdown',
                ...(!isFinal && Markup.inlineKeyboard([
                    [Markup.button.callback('⛔ DỪNG LỆNH NÀY', `stop_${msgId}`)]
                ]))
            }
        );
        if (task) task.lastUpdate = now;
    } catch (e) {
        // Bỏ qua lỗi nếu nội dung tin nhắn giống hệt cũ
    }
}

// Xử lý khi nhận lệnh văn bản
bot.on('text', async (ctx) => {
    if (ctx.from.id.toString() !== ALLOWED_ID.toString()) return;

    const command = ctx.message.text;
    
    // Gửi tin nhắn khởi tạo
    const msg = await ctx.reply(`🚀 **Exec:** \`${command}\`\n\n\`Đang chuẩn bị...\``, {
        parse_mode: 'Markdown'
    });

    const msgId = msg.message_id;
    const lines = [];

    // Chạy lệnh với stdbuf để xóa buffer hệ thống
    // detached: true kết hợp với process.kill(-pid) để giết cả nhóm tiến trình con
    const child = spawn('sh', ['-c', `stdbuf -i0 -oL -eL ${command}`], {
        detached: true,
        stdio: ['inherit', 'pipe', 'pipe']
    });

    activeTasks.set(msgId, { proc: child, lines, command, lastUpdate: 0 });

    child.stdout.on('data', (data) => {
        const str = data.toString().trim();
        if (str) {
            lines.push(...str.split('\n'));
            if (lines.length > 50) lines.shift(); // Giữ tối đa 50 dòng trong RAM
            sendUpdate(ctx, msgId, command, lines);
        }
    });

    child.stderr.on('data', (data) => {
        const str = data.toString().trim();
        if (str) {
            lines.push(`[Err] ${str}`);
            sendUpdate(ctx, msgId, command, lines);
        }
    });

    child.on('close', (code) => {
        sendUpdate(ctx, msgId, command, lines, true);
        activeTasks.delete(msgId);
    });

    child.on('error', (err) => {
        ctx.reply(`❌ Lỗi hệ thống: ${err.message}`);
        activeTasks.delete(msgId);
    });
});

// Xử lý nút dừng lệnh (Chỉ dừng đúng lệnh của tin nhắn đó)
bot.action(/^stop_(\m+)/, async (ctx) => {
    const msgId = parseInt(ctx.match[1]);
    const task = activeTasks.get(msgId);

    if (task && task.proc) {
        try {
            // Giết cả nhóm tiến trình (Nuclear Option)
            process.kill(-task.proc.pid, 'SIGKILL');
            await ctx.answerCbQuery('🛑 Đã ép dừng lệnh!');
        } catch (e) {
            try { task.proc.kill('SIGKILL'); } catch (i) {}
            await ctx.answerCbQuery('Đang dừng...');
        }
    } else {
        await ctx.answerCbQuery('Lệnh đã kết thúc hoặc không tìm thấy.');
    }
});

// Xử lý tải file trực tiếp
bot.on('document', async (ctx) => {
    if (ctx.from.id.toString() !== ALLOWED_ID.toString()) return;
    
    const fileId = ctx.message.document.file_id;
    const fileName = ctx.message.document.file_name;
    const link = await ctx.telegram.getFileLink(fileId);
    
    const response = await fetch(link.href);
    const buffer = await response.arrayBuffer();
    fs.writeFileSync(path.join(__dirname, fileName), Buffer.from(buffer));
    
    ctx.reply(`📥 Đã nhận file: \`${fileName}\` vào thư mục /app`, { parse_mode: 'Markdown' });
});

bot.launch().then(() => console.log('Bot Node.js SSH Ultra đang chạy...'));

// Đóng bot an toàn
process.once('SIGINT', () => bot.stop('SIGINT'));
process.once('SIGTERM', () => bot.stop('SIGTERM'));
EOF

# 4. Lệnh khởi chạy
CMD ["node", "index.js"]
