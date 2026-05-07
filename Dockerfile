FROM ubuntu:latest

# 1. Cài đặt môi trường
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y openssh-server python3 curl sudo && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cấu hình SSH (Cổng nội bộ cố định là 22)
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 3. Script khởi động
# SSH sẽ chạy cổng 22. Web Server sẽ chạy cổng Railway cấp ($PORT).
RUN echo '#!/bin/bash\n\
echo "root:8" | chpasswd\n\
/usr/sbin/sshd\n\
echo "------------------------------------------------"\n\
echo "🚀 SERVER ROOT:8 ĐÃ SẴN SÀNG"\n\
echo "🔑 Tài khoản: root | Mật khẩu: 8"\n\
echo "📡 SSH đang chạy cổng nội bộ: 22"\n\
echo "🌐 Web (Healthcheck) chạy cổng: ${PORT}"\n\
echo "------------------------------------------------"\n\
# Lệnh này phải dùng biến $PORT do Railway cấp, không được gán cứng là 22\n\
python3 -m http.server ${PORT}' > /start.sh && chmod +x /start.sh

# Chỉ EXPOSE 22 cho TCP Proxy
EXPOSE 22

CMD ["/start.sh"]
