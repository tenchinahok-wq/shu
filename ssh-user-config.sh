#!/bin/bash

# 1. Đặt mật khẩu Root từ biến môi trường Railway
if [ -n "$ROOT_PASSWORD" ]; then
    echo "root:$ROOT_PASSWORD" | chpasswd
    echo "✅ Root password set successfully."
else
    # Nếu bạn quên đặt biến, nó sẽ lấy pass mặc định là 'root' để bạn không bị khóa
    echo "root:root" | chpasswd
    echo "⚠️ ROOT_PASSWORD not set, using default 'root'."
fi

# 2. Cấu hình SSH Key nếu có (nhưng KHÔNG tắt password)
if [ -n "$SSH_PUBLIC_KEY" ]; then
    mkdir -p /root/.ssh
    echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
    echo "✅ SSH Key added."
fi

# 3. Khởi động SSH Server
echo "🚀 SSH Server is starting on port 22..."
exec /usr/sbin/sshd -D
