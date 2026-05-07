#!/bin/bash

echo "🚀 [SYSTEM] Đang khởi động hệ thống..."

# 1. Chạy SSH truyền thống (dự phòng)
service ssh start

# 2. Chạy Tailscale Daemon
tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
sleep 5

# 3. Kết nối Tailscale với tính năng --ssh (Đây là bí quyết)
# Tính năng --ssh của Tailscale sẽ tự quản lý cổng 22, cực kỳ ổn định trong container
if [ -z "$TAILSCALE_AUTH_KEY" ]; then
    echo "❌ LỖI: Thiếu TAILSCALE_AUTH_KEY"
    exit 1
fi

tailscale up --authkey="$TAILSCALE_AUTH_KEY" --hostname=shopee-server --accept-dns=false --ssh --force-reauth

echo "--------------------------------------"
echo "✅ HỆ THỐNG ĐÃ ONLINE!"
echo "🔗 IP: $(tailscale ip -4)"
echo "💡 Mẹo: Dùng 'tailscale ssh shopee@shopee-server' hoặc IP trên Termius"
echo "--------------------------------------"

# 4. Keep-alive Web Server
LISTENING_PORT=${PORT:-8080}
python3 -m http.server $LISTENING_PORT &

# 5. Vòng lặp siêu cấp để Railway không bao giờ tắt được bạn
while true; do
    # Tự tạo traffic nội bộ và in log để Railway thấy "sự sống"
    curl -s http://localhost:$LISTENING_PORT > /dev/null
    echo "[KEEP-ALIVE] Heartbeat sent at $(date)"
    
    # Nếu Tailscale bị rớt, tự động reconnect
    if ! tailscale status > /dev/null; then
        echo "⚠️ Tailscale rớt mạng, đang kết nối lại..."
        tailscale up --authkey="$TAILSCALE_AUTH_KEY" --hostname=shopee-server --accept-dns=false --ssh
    fi
    
    sleep 20
done
