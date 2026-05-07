#!/bin/bash

echo "🚀 [SYSTEM] Đang khởi động hệ thống..."

# 1. Dọn dẹp trạng thái cũ để tránh lỗi 404 node not found
rm -rf /var/lib/tailscale/tailscaled.state

# 2. Khởi động SSH Server
service ssh start

# 3. Khởi động Tailscale Daemon (Chế độ Userspace cho Railway)
tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
sleep 5

# 4. Kết nối mạng Tailscale
if [ -z "$TAILSCALE_AUTH_KEY" ]; then
    echo "⚠️ CẢNH BÁO: TAILSCALE_AUTH_KEY trống. Chỉ có thể dùng Web Terminal."
else
    echo "☁️ Đang kết nối Tailscale..."
    tailscale up --authkey="$TAILSCALE_AUTH_KEY" --hostname=shopee-server --accept-dns=false --ssh --force-reauth
    echo "✅ IP Tailscale: $(tailscale ip -4)"
fi

# 5. Khởi động Web Terminal (ttyd) trên Port mà Railway cấp
echo "🌐 Khởi động Web Terminal tại Port: ${PORT:-8080}"
# Lưu ý: -c user:pass để bảo mật web terminal của bạn
/bin/ttyd -p ${PORT:-8080} -c shopee:shopee /bin/bash &

# 6. Vòng lặp Keep-alive (Duy trì sự sống cho Railway)
while true; do
    # Tự ping chính mình để Railway thấy traffic
    curl -s http://localhost:${PORT:-8080} > /dev/null
    echo "[HEARTBEAT] Hệ thống vẫn online: $(date)"
    sleep 30
done
