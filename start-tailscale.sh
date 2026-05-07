#!/bin/bash

echo "🚀 [SYSTEM] Đang khởi động dịch vụ..."

# 1. Chạy SSH
service ssh start
echo "✅ SSH đã sẵn sàng."

# 2. Khởi động Tailscale Daemon (Chế độ Userspace)
tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &

# 3. Đăng nhập và kết nối vào mạng Tailscale
# Đợi daemon khởi động xong rồi mới chạy lệnh up
sleep 2
tailscale up --authkey="$TAILSCALE_AUTH_KEY" --hostname=shopee-server --accept-dns=false

echo "--------------------------------------"
echo "✅ Kết nối Tailscale THÀNH CÔNG!"
echo "🛠️  Nodejs: $(node -v) | Go: $(go version)"
echo "👤 User: shopee | Pass: shopee"
echo "--------------------------------------"

# 4. Giữ container sống (Bắt đúng Port của Railway)
LISTENING_PORT=${PORT:-8080}
echo "🌐 Lắng nghe tại cổng: $LISTENING_PORT"
python3 -m http.server $LISTENING_PORT
