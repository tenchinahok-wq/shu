#!/bin/bash

echo "🚀 [SYSTEM] Đang khởi động hệ thống với tài khoản shopee..."

# 1. Khởi động SSH
service ssh start

# 2. Xử lý Token (Tự gán Token của bạn nếu biến môi trường trống)
DEFAULT_TOKEN="eyJhIjoiZDY0YjZkZTUxODljNzU3M2ExNjYwNTgxMmU5YzU1N2IiLCJ0IjoiOTcyMGMzZTktY2NmZi00MDhiLTgyZmUtMDEzYjViMTdlNDkxIiwicyI6Ik5UZzBaRFJpT1dZdE1USXhOUzAwWlRCakxXRmpNVGN0TWpreE1qVTBPVEZqWlRFeiJ9"
TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN:-$DEFAULT_TOKEN}

echo "☁️  Đang kết nối Cloudflare Tunnel..."
cloudflared tunnel --no-autoupdate run --token "$TUNNEL_TOKEN" > /tmp/cloudflared.log 2>&1 &

# 3. Thông báo thông tin
echo "--------------------------------------"
echo "✅ Trạng thái: Đã sẵn sàng!"
echo "👤 User/Pass SSH: shopee / shopee"
echo "🛠️  Nodejs: $(node -v)"
echo "🛠️  Golang: $(go version)"
echo "--------------------------------------"

# 4. FIX LỖI SIGNAL 15: Bắt buộc bind đúng Port của nền tảng (Railway/Render)
# Nếu hệ thống cấp port nào thì dùng port đó, không thì dùng 8080
LISTENING_PORT=${PORT:-8080}
echo "🌐 Đang lắng nghe tại cổng: $LISTENING_PORT"

# Chạy Web Server ở chế độ Foreground để giữ container không bị thoát
python3 -m http.server $LISTENING_PORT
