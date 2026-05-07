# Sử dụng Node.js bản 20
FROM node:20-slim

# Cài đặt các công cụ hệ thống cần thiết
RUN apt-get update && apt-get install -y \
    curl wget git htop neofetch coreutils \
    build-essential iputils-ping dnsutils net-tools vim \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Khởi tạo project và cài đặt thư viện Telegraf
RUN npm init -y && npm install telegraf

# Tạo file index.js trực tiếp bên trong Dockerfile
RUN cat <<'EOF' > index.js
const { Telegraf, Markup } = require('telegraf');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const bot = new Telegraf(process.env.TK);
const ALLOWED_ID = process.env.ID;
const LOG_LIMIT = 10;

let currentProcess = null;
let lastMsgId = null;
let logLines = [];
let lastUpdateTime = 0;

// Hàm cập nhật tin nhắn log lên Telegram
async function updateLog(ctx, command, isFinal = false) {
  const now = Date.now();
  // Giới hạn 1.2 giây mỗi lần update để tránh bị Telegram chặn
  if (!isFinal && now - lastUpdateTime < 1200) return;

  const output = logLines.slice(-LOG_LIMIT).join('\n') || 'Đang chờ output...';
  const status = isFinal ? '✅ Hoàn thành' : '🚀 Running';
  const text = `**${status}:** \`${command}\`\n\n\`\`\`text\n${output}\n\`\`\``;

  try {
    await ctx.telegram.editMessageText(
      ctx.chat.id,
      lastMsgId,
      null,
      text,
      {
        parse_mode: 'Markdown',
        ...(!isFinal && Markup.inlineKeyboard([
          Markup.button.callback('⛔ Dừng lệnh', 'stop_cmd')
        ]))
      }
    );
    lastUpdateTime = now;
  } catch (e) {
    // Bỏ qua lỗi nếu nội dung không đổi
  }
}

// Xử lý lệnh văn bản
bot.on('text', async (ctx) => {
  if (ctx.from.id.toString() !== ALLOWED_ID.toString()) return;

  if (currentProcess) {
    return ctx.reply('⚠️ Có lệnh đang chạy. Hãy dừng nó trước.');
  }

  const command = ctx.message.text;
  logLines = [];
  
  // Xóa log cũ
  if (lastMsgId) {
    try { await ctx.deleteMessage(lastMsgId); } catch (e) {}
  }

  const msg = await ctx.reply(`🚀 **Đang chạy:** \`${command}\`\n\n\`Đang khởi động...\``, {
    parse_mode: 'Markdown',
    ...Markup.inlineKeyboard([Markup.button.callback('⛔ Dừng lệnh', 'stop_cmd')])
  });
  
  lastMsgId = msg.message_id;

  // Chạy lệnh bằng spawn để lấy stream trực tiếp
  // Sử dụng 'sh -c' để hỗ trợ các lệnh phức tạp
  currentProcess = spawn('sh', ['-c', `stdbuf -i0 -oL -eL ${command}`], {
    detached: true,
    stdio: ['inherit', 'pipe', 'pipe']
  });

  currentProcess.stdout.on('data', (data) => {
    const str = data.toString().trim();
    if (str) {
      logLines.push(...str.split('\n'));
      updateLog(ctx, command);
    }
  });

  currentProcess.stderr.on('data', (data) => {
    const str = data.toString().trim();
    if (str) {
      logLines.push(`[Error] ${str}`);
      updateLog(ctx, command);
    }
  });

  currentProcess.on('close', (code) => {
    updateLog(ctx, command, true);
    currentProcess = null;
  });
});

// Xử lý nút dừng lệnh
bot.action('stop_cmd', async (ctx) => {
  if (currentProcess) {
    try {
      // Giết cả nhóm tiến trình
      process.kill(-currentProcess.pid, 'SIGTERM');
      await ctx.answerCbQuery('Đã gửi lệnh dừng.');
    } catch (e) {
      try { currentProcess.kill(); } catch (e2) {}
      await ctx.answerCbQuery('Đang dừng tiến trình...');
    }
  } else {
    await ctx.answerCbQuery('Không có lệnh nào đang chạy.');
  }
});

// Xử lý tải file
bot.on('document', async (ctx) => {
  if (ctx.from.id.toString() !== ALLOWED_ID.toString()) return;
  
  const fileId = ctx.message.document.file_id;
  const fileName = ctx.message.document.file_name;
  const link = await ctx.telegram.getFileLink(fileId);
  
  const response = await fetch(link.href);
  const buffer = await response.arrayBuffer();
  fs.writeFileSync(path.join(__dirname, fileName), Buffer.from(buffer));
  
  ctx.reply(`📥 Đã tải file: \`${fileName}\` vào thư mục /app`, { parse_mode: 'Markdown' });
});

bot.catch((err) => console.error('Bot Error:', err));

bot.launch().then(() => console.log('Bot Node.js đang chạy...'));

// Đóng bot an toàn khi container bị tắt
process.once('SIGINT', () => bot.stop('SIGINT'));
process.once('SIGTERM', () => bot.stop('SIGTERM'));
EOF

# Chạy bot
CMD ["node", "index.js"]
