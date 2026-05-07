#!/bin/bash

echo "🚀 [SYSTEM] Đang khởi động dịch vụ..."

# Xóa các file rác cũ nếu có để tránh lỗi 'node not found'
rm -rf /var/lib/tailscale/tailscaled.state

# 1. Chạy SSH
service ssh start

# 2. Khởi động Tailscale Daemon
tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &

# Đợi daemon sẵn sàng
sleep 3

# 3. Đăng nhập Tailscale
# Sử dụng --force-reauth để làm mới node nếu gặp lỗi 404
if [ -n "$TAILSCALE_AUTH_KEY" ]; then
    tailscale up --authkey="$TAILSCALE_AUTH_KEY" --hostname=shopee-server --accept-dns=false --force-reauth
else
    echo "❌ LỖI: Không tìm thấy TAILSCALE_AUTH_KEY"
    exit 1
fi

echo "--------------------------------------"
echo "✅ Kết nối Tailscale THÀNH CÔNG!"
echo "🛠️  IP: $(tailscale ip -4)"
echo "--------------------------------------"

# 4. Keep-alive (Fix Signal 15)
LISTENING_PORT=${PORT:-8080}
python3 -m http.server $LISTENING_PORT &

# Vòng lặp giữ container không thoát
while true; do
    sleep 60
    echo "Hệ thống vẫn đang chạy: $(date)"
done
