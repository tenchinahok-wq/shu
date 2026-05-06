#!/bin/bash

echo "--- DEBUG INFO START ---"
echo "Current User: $(whoami)"
echo "Checking SSH Config..."
grep "PermitRootLogin" /etc/ssh/sshd_config
grep "PasswordAuthentication" /etc/ssh/sshd_config
echo "--- DEBUG INFO END ---"

# Đặt pass cho root
if [ -n "$ROOT_PASSWORD" ]; then
    echo "root:$ROOT_PASSWORD" | chpasswd
    echo "✅ Root password has been set."
else
    echo "root:root" | chpasswd
    echo "⚠️ ROOT_PASSWORD not set, using default 'root'."
fi

# Cấu hình SSH Key nếu có
if [ -n "$SSH_PUBLIC_KEY" ]; then
    mkdir -p /root/.ssh
    echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
    echo "✅ SSH Key added for root."
fi

echo "🚀 Starting SSH Server in Debug Mode..."
# -D: Chạy không ngầm
# -e: Xuất log ra stderr (hiển thị lên Railway Logs)
exec /usr/sbin/sshd -D -e
