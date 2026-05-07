# Giai đoạn 1: Build
FROM node:20-bookworm AS builder
WORKDIR /app

# Cài đặt thư viện
RUN npm install telegraf axios

# Tạo mã nguồn index.js
RUN cat <<'EOF' > index.js
const { Telegraf, Markup } = require('telegraf');
const { spawn } = require('child_process');
const fs = require('fs');
const axios = require('axios');
const path = require('path');

const bot = new Telegraf(process.env.TK);
const ADMIN_ID = parseInt(process.env.ID);
const activeProcs = new Map(); // Lưu PID và dữ liệu theo message_id

// Middleware kiểm tra quyền Admin
bot.use((ctx, next) => {
    if (ctx.from && ctx.from.id === ADMIN_ID) return next();
});

// 1. XỬ LÝ LƯU FILE
bot.on('document', async (ctx) => {
    try {
        const fileId = ctx.message.document.file_id;
        const fileName = ctx.message.document.file_name;
        const link = await ctx.telegram.getFileLink(fileId);
        
        const response = await axios({ url: link.href, responseType: 'stream' });
        response.data.pipe(fs.createWriteStream(path.join(__dirname, fileName)));
        
        ctx.reply(`📥 Đã lưu file: \`${fileName}\``, { parse_mode: 'Markdown' });
    } catch (err) {
        ctx.reply("❌ Lỗi lưu file: " + err.message);
    }
});

// 2. XỬ LÝ NÚT DỪNG
bot.on('callback_query', (ctx) => {
    const data = ctx.callbackQuery.data;
    if (data.startsWith('stop_')) {
        const msgId = data.split('_')[1];
        const procInfo = activeProcs.get(parseInt(msgId));
        
        if (procInfo && procInfo.child) {
            try {
                // Nuclear Kill: Giết cả nhóm tiến trình
                process.kill(-procInfo.child.pid, 'SIGKILL');
                ctx.answerCbQuery("Đang dừng lệnh...");
            } catch (e) {
                ctx.answerCbQuery("Không thể dừng hoặc đã xong.");
            }
        } else {
            ctx.answerCbQuery("Lệnh không còn tồn tại.");
        }
    }
});

// 3. XỬ LÝ CHẠY LỆNH (ĐA LUỒNG)
bot.on('text', async (ctx) => {
    const cmdStr = ctx.message.text;
    const msg = await ctx.reply(`🚀 **Exec:** \`${cmdStr}\``, {
        parse_mode: 'Markdown',
        ...Markup.inlineKeyboard([Markup.button.callback('⛔ DỪNG LỆNH', `stop_${ctx.message.message_id + 1}`)])
    });

    // ID tin nhắn mà bot sẽ edit (thường là msg.message_id)
    const targetMsgId = msg.message_id;
    let logs = [];
    
    // Khởi chạy tiến trình
    const child = spawn('sh', ['-c', `stdbuf -oL -eL ${cmdStr}`], {
        detached: true, // Tạo process group riêng
        stdio: ['ignore', 'pipe', 'pipe']
    });

    activeProcs.set(targetMsgId, { child, logs });

    child.stdout.on('data', (data) => {
        logs.push(data.toString());
        if (logs.length > 12) logs.shift();
    });

    child.stderr.on('data', (data) => {
        logs.push(data.toString());
        if (logs.length > 12) logs.shift();
    });

    // Cập nhật giao diện mỗi 1.5s
    const ticker = setInterval(() => {
        if (logs.length > 0) {
            const output = logs.join('').trim();
            ctx.telegram.editMessageText(ctx.chat.id, targetMsgId, null, 
                `🚀 **Running:** \`${cmdStr}\` \n\n\`\`\`text\n${output}\n\`\`\``,
                { 
                    parse_mode: 'Markdown',
                    ...Markup.inlineKeyboard([Markup.button.callback('⛔ DỪNG LỆNH', `stop_${targetMsgId}`)])
                }
            ).catch(() => {});
        }
    }, 1500);

    const cleanup = (status) => {
        clearInterval(ticker);
        activeProcs.delete(targetMsgId);
        ctx.telegram.editMessageText(ctx.chat.id, targetMsgId, null, 
            `${status}: \`${cmdStr}\` \n\n\`Tiến trình kết thúc.\``, 
            { parse_mode: 'Markdown' }
        ).catch(() => {});
    };

    child.on('close', (code) => cleanup(code === 0 ? '✅ Hoàn thành' : '🛑 Đã dừng'));
    child.on('error', (err) => cleanup('❌ Lỗi: ' + err.message));
});

bot.launch();
console.log("Bot Node.js đang chạy...");
EOF

# Giai đoạn 2: Runtime
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y nodejs npm ca-certificates coreutils curl wget git htop iputils-ping dnsutils net-tools && apt-get clean
WORKDIR /app
COPY --from=builder /app/index.js .
COPY --from=builder /app/node_modules ./node_modules
CMD ["node", "index.js"]
