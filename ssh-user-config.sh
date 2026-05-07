#!/bin/bash

# 1. Đặt mật khẩu Root
ROOT_PASSWORD=${ROOT_PASSWORD:-"root"}
echo "root:$ROOT_PASSWORD" | chpasswd
echo "--- [LOG] Root password set ---"

# 2. Tạo file Log
LOG_FILE="/tmp/ssh_debug.log"
touch $LOG_FILE

# 3. Chạy SSH Server ở cổng 22 (Background)
/usr/sbin/sshd -E $LOG_FILE
echo "--- [LOG] SSH Server started on port 22 ---"

# 4. Tạo trang HTML log
cat <<EOF > /tmp/index.html
<!DOCTYPE html>
<html>
<head>
    <title>SSH Live Logs</title>
    <meta http-equiv="refresh" content="3">
    <style>
        body { background: #000; color: #0f0; font-family: monospace; padding: 20px; }
        pre { background: #111; padding: 15px; border: 1px solid #333; }
    </style>
</head>
<body>
    <h2>🚀 SSH Debugger</h2>
    <p>Status: Running | Port: 22</p>
    <pre>$(tail -n 50 $LOG_FILE)</pre>
</body>
</html>
EOF

# 5. Chạy Web Server ở cổng 80 (Để Railway Healthcheck nó thấy)
echo "--- [LOG] Web Server starting on port 80 ---"
cd /tmp
python3 -m http.server 80
