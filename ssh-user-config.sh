#!/bin/bash

# 1. Đặt mật khẩu Root
ROOT_PASSWORD=${ROOT_PASSWORD:-"root"}
echo "root:$ROOT_PASSWORD" | chpasswd
echo "✅ Password set for Root."

# 2. Tạo file log để hiển thị lên Web
LOG_FILE="/var/log/ssh_web.log"
touch $LOG_FILE
chmod 644 $LOG_FILE

# 3. Khởi động SSH Server (Chạy ngầm và ném log vào file)
/usr/sbin/sshd -E $LOG_FILE
echo "🚀 SSH Server started in background."

# 4. Tạo một trang HTML đơn giản để xem log
cat <<EOF > index.html
<!DOCTYPE html>
<html>
<head>
    <title>SSH Live Logs</title>
    <meta http-equiv="refresh" content="5">
    <style>
        body { background: #1e1e1e; color: #00ff00; font-family: monospace; padding: 20px; }
        h2 { color: #fff; border-bottom: 1px solid #444; }
        pre { white-space: pre-wrap; word-wrap: break-word; }
    </style>
</head>
<body>
    <h2>-- SSH REALTIME DEBUG LOGS --</h2>
    <p>Status: Running | Root Pass: ${ROOT_PASSWORD}</p>
    <pre>$(tail -n 50 $LOG_FILE)</pre>
</body>
</html>
EOF

echo "🌐 Web Log Server starting on port 80..."
# 5. Chạy Web Server ở chế độ chính để giữ container không bị tắt
# Cổng 80 sẽ giúp Railway Healthcheck luôn báo "Active"
python3 -m http.server 80
