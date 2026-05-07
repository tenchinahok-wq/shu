FROM ubuntu:latest

# 1. Cài đặt các thành phần cần thiết
# Build-time only - ngăn các câu hỏi tương tác
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    openssh-server \
    python3 \
    curl \
    sudo \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cấu hình SSH Server
RUN mkdir /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo "TCPKeepAlive yes" >> /etc/ssh/sshd_config

# 3. Tạo script khởi động trực tiếp trong Dockerfile
# Script này sẽ: gán pass, chạy SSH, và chạy web server giữ mạng
RUN echo '#!/bin/bash\n\
echo "root:${Password:-shopee}" | chpasswd\n\
/usr/sbin/sshd\n\
echo "------------------------------------------------"\n\
echo "✅ SSH Server đang chạy tại cổng nội bộ 22"\n\
echo "✅ Healthcheck đang chạy tại cổng ${PORT:-8080}"\n\
echo "------------------------------------------------"\n\
python3 -m http.server ${PORT:-8080}' > /start.sh && chmod +x /start.sh

# Railway dùng cổng 22 cho TCP Proxy và PORT (8080) cho HTTP
EXPOSE 22 8080

# Chạy script khi container khởi động
CMD ["/start.sh"]
