#!/bin/bash

echo "🚀 [SYSTEM] Đang khởi động hệ thống..."

# 1. Khởi động SSH
service ssh start
echo "✅ SSH Service đã chạy."

# 2. Khởi động Tailscale Daemon (Chế độ Userspace cho Cloud)
tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &

# Đợi daemon sẵn sàng
sleep 5

# 3. Đăng nhập Tailscale
if [ -z "$TAILSCALE_AUTH_KEY" ]; then
    echo "❌ LỖI: Chưa có TAILSCALE_AUTH_KEY trong Variables!"
    exit 1
fi

echo "☁️  Đang kết nối vào mạng Tailscale..."
tailscale up --authkey="$TAILSCALE_AUTH_KEY" --hostname=shopee-server --accept-dns=false --force-reauth

echo "--------------------------------------"
echo "✅ HỆ THỐNG ĐÃ ONLINE!"
echo "👤 User: shopee | Pass: shopee"
echo "🔗 IP Tailscale: $(tailscale ip -4)"
echo "🛠️  Nodejs: $(node -v) | Go: $(go version)"
echo "--------------------------------------"

# 4. FIX LỖI SIGNAL 15 & KEEP-ALIVE
LISTENING_PORT=${PORT:-8080}
echo "🌐 Đang duy trì cổng $LISTENING_PORT..."

# Chạy web server ảo ở nền
python3 -m http.server $LISTENING_PORT &

# Vòng lặp vô tận tự gọi chính mình để không bị Railway tắt
while true; do
    # Tự ping chính mình để tạo traffic giả
    curl -s http://localhost:$LISTENING_PORT > /dev/null
    echo "Hệ thống vẫn đang sống: $(date)"
    # Nghỉ 30 giây trước khi ping lại
    sleep 30
done
