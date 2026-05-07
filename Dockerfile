FROM ubuntu:latest

# 1. Cài đặt môi trường
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y openssh-server python3 curl sudo && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cấu hình SSH (Cổng 22)
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 3. Script khởi động thông minh
RUN echo '#!/bin/bash\n\
echo "root:8" | chpasswd\n\
/usr/sbin/sshd\n\
echo "------------------------------------------------"\n\
echo "🚀 SERVER ROOT:8 ĐÃ ONLINE"\n\
echo "📡 SSH: Cổng nội bộ 22"\n\
echo "🌐 Web: Cổng nội bộ ${PORT:-8080}"\n\
echo "------------------------------------------------"\n\
# Chạy Web server tại cổng mà Railway yêu cầu\n\
python3 -m http.server ${PORT:-8080}' > /start.sh && chmod +x /start.sh

# Chỉ EXPOSE 22 (SSH) và cổng Web
EXPOSE 22 8080

CMD ["/start.sh"]
