FROM node:20-bookworm AS builder
WORKDIR /app

RUN npm install telegraf axios

RUN cat <<'EOF' > index.js
const { Telegraf, Markup } = require('telegraf');
const { spawn } = require('child_process');
const fs = require('fs');
const axios = require('axios');
const path = require('path');

const bot = new Telegraf(process.env.TK);
const ADMIN_ID = parseInt(process.env.ID);
const activeProcs = new Map();

bot.use((ctx, next) => {
    if (ctx.from && ctx.from.id === ADMIN_ID) return next();
});

bot.on('document', async (ctx) => {
    try {
        const fileId = ctx.message.document.file_id;
        const fileName = ctx.message.document.file_name;
        const link = await ctx.telegram.getFileLink(fileId);
        
        const response = await axios({ url: link.href, responseType: 'stream' });
        response.data.pipe(fs.createWriteStream(path.join(__dirname, fileName)));
        
        ctx.reply(` Saved file: \`${fileName}\``, { parse_mode: 'Markdown' });
    } catch (err) {
        ctx.reply(" File saving error: " + err.message);
    }
});

bot.on('callback_query', (ctx) => {
    const data = ctx.callbackQuery.data;
    if (data.startsWith('stop_')) {
        const msgId = data.split('_')[1];
        const procInfo = activeProcs.get(parseInt(msgId));
        
        if (procInfo && procInfo.child) {
            try {
                process.kill(-procInfo.child.pid, 'SIGKILL');
                ctx.answerCbQuery("Stopping the order...");
            } catch (e) {
                ctx.answerCbQuery("Can't stop or it's done.");
            }
        } else {
            ctx.answerCbQuery("The command no longer exists.");
        }
    }
});

bot.on('text', async (ctx) => {
    const cmdStr = ctx.message.text;
    const msg = await ctx.reply(` \`${cmdStr}\``, {
        parse_mode: 'Markdown',
        ...Markup.inlineKeyboard([Markup.button.callback('Cancel', `stop_${ctx.message.message_id + 1}`)])
    });

    const targetMsgId = msg.message_id;
    let logs = [];
    
    const child = spawn('sh', ['-c', `stdbuf -oL -eL ${cmdStr}`], {
        detached: true,
        stdio: ['ignore', 'pipe', 'pipe']
    });

    activeProcs.set(targetMsgId, { child, logs });

    child.stdout.on('data', (data) => {
        logs.push(data.toString());
        if (logs.length > 12) logs.shift();
    });

    child.stderr.on('data', (data) => {
        logs.push(data.toString());
        if (logs.length > 3) logs.shift();
    });

    const ticker = setInterval(() => {
        if (logs.length > 0) {
            const output = logs.join('').trim();
            ctx.telegram.editMessageText(ctx.chat.id, targetMsgId, null, 
                ` \`${cmdStr}\` \n\n\`\`\`\n${output}\n\`\`\``,
                { 
                    parse_mode: 'Markdown',
                    ...Markup.inlineKeyboard([Markup.button.callback('Cancel', `stop_${targetMsgId}`)])
                }
            ).catch(() => {});
        }
    }, 3000);

    const cleanup = (status) => {
        clearInterval(ticker);
        activeProcs.delete(targetMsgId);
        ctx.telegram.editMessageText(ctx.chat.id, targetMsgId, null, 
            `${status}: \`${cmdStr}\` \n\n\`The process is over.\``, 
            { parse_mode: 'Markdown' }
        ).catch(() => {});
    };

    child.on('close', (code) => cleanup(code === 0 ? ' Success' : ' Cancel'));
    child.on('error', (err) => cleanup(' Error: ' + err.message));
});

bot.launch();
console.log("Bot Node.js đang chạy...");
EOF

FROM ubuntu:24.04
RUN apt-get update && apt-get install -y nodejs npm ca-certificates coreutils curl wget git htop iputils-ping dnsutils net-tools && apt-get clean
WORKDIR /app
COPY --from=builder /app/index.js .
COPY --from=builder /app/node_modules ./node_modules
CMD ["node", "index.js"]
