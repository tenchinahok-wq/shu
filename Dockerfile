FROM ubuntu:latest

# 1. Cài đặt môi trường
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y openssh-server python3 curl sudo && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cấu hình SSH (Cổng nội bộ 22)
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 3. Script khởi động thông minh
# Lưu ý: SSH chạy cổng 22, Python chạy cổng $PORT (Railway tự cấp, thường là 8080)
RUN echo '#!/bin/bash\n\
echo "root:8" | chpasswd\n\
/usr/sbin/sshd\n\
echo "------------------------------------------------"\n\
echo "🚀 SERVER ROOT:8 ĐÃ SẴN SÀNG"\n\
echo "🔑 Tài khoản: root | Mật khẩu: 8"\n\
echo "📡 SSH đang chờ tại cổng nội bộ: 22"\n\
echo "🌐 Web đang chờ tại cổng Railway: ${PORT:-8080}"\n\
echo "------------------------------------------------"\n\
# Chạy web server để Railway không tắt container\n\
python3 -m http.server ${PORT:-8080}' > /start.sh && chmod +x /start.sh

# Chỉ EXPOSE cổng cần thiết
EXPOSE 22

CMD ["/start.sh"]
