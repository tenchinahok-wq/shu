#!/bin/bash

echo "🚀 [SYSTEM] Đang khởi động với Tailscale..."

# 1. Khởi động SSH
service ssh start

# 2. Khởi động Tailscale Daemon
tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &

# 3. Đăng nhập Tailscale
# Tự động dùng TAILSCALE_AUTH_KEY từ biến môi trường
if [ -z "$TAILSCALE_AUTH_KEY" ]; then
    echo "⚠️ THIẾU TAILSCALE_AUTH_KEY! Bạn sẽ không thể kết nối từ xa."
else
    tailscale up --authkey="$TAILSCALE_AUTH_KEY" --hostname=shopee-server --accept-dns=false
fi

echo "--------------------------------------"
echo "✅ Hệ thống đã sẵn sàng!"
echo "🛠️  Nodejs: $(node -v) | Go: $(go version)"
echo "🔗 Kết nối SSH thẳng tới IP của Tailscale"
echo "--------------------------------------"

# 4. Keep-alive (Fix lỗi Signal 15)
LISTENING_PORT=${PORT:-8080}
python3 -m http.server $LISTENING_PORT
