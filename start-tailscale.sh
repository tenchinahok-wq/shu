# ... (Phần trên giữ nguyên đến đoạn tailscale up)

echo "--------------------------------------"
echo "✅ Kết nối Tailscale THÀNH CÔNG!"
echo "🛠️  Nodejs: $(node -v) | Go: $(go version)"
echo "🔗 IP Tailscale của bạn: $(tailscale ip -4)"
echo "--------------------------------------"

# Thay thế đoạn python server bằng vòng lặp chống thoát và phản hồi Port
LISTENING_PORT=${PORT:-8080}
echo "🌐 Đang duy trì cổng $LISTENING_PORT cho Railway..."

# Chạy một server web nền và giữ script chạy mãi mãi
python3 -m http.server $LISTENING_PORT &

# Vòng lặp vô tận để giữ container không bao giờ thoát
while true; do
    sleep 60
    # In ra log mỗi phút để Railway biết mình vẫn sống
    echo "Hệ thống vẫn đang chạy: $(date)"
done
