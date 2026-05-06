#!/bin/bash

# 1. Thiết lập mật khẩu cho Root (Lấy từ biến ROOT_PASSWORD trên Railway)
if [ -n "$ROOT_PASSWORD" ]; then
    echo "root:$ROOT_PASSWORD" | chpasswd
    echo "✅ Root password has been set."
else
    echo "⚠️ WARNING: ROOT_PASSWORD is not set. Using default or no password."
fi

# 2. Thiết lập SSH Public Key cho Root (Nếu bạn muốn dùng Key cho "ngọt")
if [ -n "$SSH_PUBLIC_KEY" ]; then
    mkdir -p /root/.ssh
    echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
    echo "✅ SSH Public Key has been configured for Root."
fi

# 3. Khởi động SSH Server ở chế độ không chạy ngầm để giữ Container sống
echo "🚀 Starting SSH Server..."
exec /usr/sbin/sshd -D
