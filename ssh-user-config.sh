#!/bin/bash

# 1. Thiết lập mật khẩu
ROOT_PASSWORD=${ROOT_PASSWORD:-"root"}
echo "root:$ROOT_PASSWORD" | chpasswd
echo "--- [LOG] Root password initialized ---"

# 2. Chuẩn bị file Log Web
LOG_FILE="/var/log/ssh_debug.log"
touch $LOG_FILE
chmod 644 $LOG_FILE

# 3. Chạy SSH Server ở chế độ nền (Background)
# Đẩy mọi log vào file để Web có cái mà hiển thị
/usr/sbin/sshd -E $LOG_FILE
echo "--- [LOG] SSH Server is running in background ---"

# 4. Tạo trang chủ HTML (vào đúng thư mục tạm)
cd /tmp
cat <<EOF > index.html
<!DOCTYPE html>
<html>
<head>
    <title>SSH Live Debug</title>
    <meta http-equiv="refresh" content="5">
    <style>
        body { background: #000; color: #0f0; font-family: 'Courier New', monospace; padding: 20px; }
        .log-box { background: #111; border: 1px solid #333; padding: 15px; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>📟 System Status: ONLINE</h1>
    <div class="log-box">
        <pre>$(tail -n 30 $LOG_FILE)</pre>
    </div>
</body>
</html>
EOF

# 5. CHỐT HẠ: Chạy Web Server theo Port của Railway
# Railway bắt buộc app web phải chạy ở cổng biến \$PORT
WEB_PORT=${PORT:-80}
echo "--- [LOG] Web Server starting on port $WEB_PORT ---"

# Chạy lệnh này ở cuối cùng để giữ container sống
python3 -m http.server $WEB_PORT
