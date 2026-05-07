#!/bin/bash

# 1. Khởi động SSH
service ssh start
echo "✅ SSH Service started (Port 22)"

# 2. Token Cloudflare của bạn
# (Tốt nhất là đặt biến môi trường, nhưng tôi sẽ dán trực tiếp vào đây theo yêu cầu của bạn)
MY_TOKEN="eyJhIjoiZDY0YjZkZTUxODljNzU3M2ExNjYwNTgxMmU5YzU1N2IiLCJ0IjoiOTcyMGMzZTktY2NmZi00MDhiLTgyZmUtMDEzYjViMTdlNDkxIiwicyI6Ik5UZzBaRFJpT1dZdE1USXhOUzAwWlRCakxXRmpNVGN0TWpreE1qVTBPVEZqWlRFeiJ9"

# Sử dụng Token từ biến môi trường nếu có, nếu không thì dùng MY_TOKEN mặc định
FINAL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN:-$MY_TOKEN}

echo "🚀 Đang khởi động Cloudflare Tunnel..."
cloudflared tunnel --no-autoupdate run --token "$FINAL_TOKEN" > /tmp/cloudflared.log 2>&1 &

# 3. Hiển thị thông tin môi trường
echo "--------------------------------------"
echo "🛠️  MÔI TRƯỜNG ĐÃ SẴN SÀNG:"
echo "Node.js: $(node -v)"
echo "Go:      $(go version)"
echo "SSH User: trthaodev"
echo "SSH Pass: thaodev@"
echo "--------------------------------------"

# 4. Giữ Container sống (Keep-alive cho Railway/Render)
echo "🌐 Container đang chạy HTTP Server tại port 8080..."
python3 -m http.server 8080
