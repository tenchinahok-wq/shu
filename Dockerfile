FROM ubuntu:latest

# 1. Cập nhật và cài đặt sạch sẽ từ đầu
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y openssh-server python3 curl sudo && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cấu hình SSH để cho phép root đăng nhập
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo "TCPKeepAlive yes" >> /etc/ssh/sshd_config

# 3. Script khởi động: Gán pass root = 8 và chạy server
# Lệnh python3 ở cuối giúp "đánh lừa" Railway không tắt container
RUN echo '#!/bin/bash\n\
echo "root:8" | chpasswd\n\
/usr/sbin/sshd\n\
echo "------------------------------------------------"\n\
echo "🚀 SERVER ĐÃ ONLINE - TÀI KHOẢN ROOT"\n\
echo "🔑 Mật khẩu mặc định: 8"\n\
echo "📡 Đang giữ cổng ${PORT:-8080} cho Railway"\n\
echo "------------------------------------------------"\n\
python3 -m http.server ${PORT:-8080}' > /start.sh && chmod +x /start.sh

# Port 22 cho SSH, Port 8080 cho Railway Healthcheck
EXPOSE 22 8080

CMD ["/start.sh"]
