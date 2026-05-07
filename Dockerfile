FROM ubuntu:latest

# 1. Cài đặt môi trường sạch
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y openssh-server python3 curl sudo && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cấu hình SSH (Cổng 22)
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 3. Script khởi động: Ép Web chạy 8080 để thoát lỗi
RUN echo '#!/bin/bash\n\
echo "root:8" | chpasswd\n\
/usr/sbin/sshd\n\
echo "------------------------------------------------"\n\
echo "🚀 SERVER ROOT:8 ĐÃ ONLINE"\n\
echo "🔑 Tài khoản: root | Mật khẩu: 8"\n\
echo "📡 SSH: Cổng nội bộ 22 (Dùng TCP Proxy)"\n\
echo "🌐 Web Healthcheck: Cổng nội bộ 8080"\n\
echo "------------------------------------------------"\n\
# Ép chạy cổng 8080 để không bao giờ bị trùng với SSH cổng 22\n\
python3 -m http.server 8080' > /start.sh && chmod +x /start.sh

# Railway sẽ nhìn vào EXPOSE để biết cổng nào là chính
EXPOSE 8080 22

CMD ["/start.sh"]
