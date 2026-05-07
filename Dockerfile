FROM ubuntu:latest

# 1. Cài đặt môi trường và các công cụ network cần thiết
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    openssh-server \
    python3 \
    curl \
    sudo \
    netcat-openbsd \
    iproute2 \
    net-tools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cấu hình SSH (Cổng 22)
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 3. Script khởi động: Fix lỗi nc và chống sập
RUN echo '#!/bin/bash\n\
echo "root:8" | chpasswd\n\
\n\
# Khởi động SSH lần đầu\n\
/usr/sbin/sshd\n\
\n\
# Khởi động Web Server (Healthcheck) chạy ngầm tại cổng 8080\n\
python3 -m http.server 8080 > /dev/null 2>&1 &\n\
\n\
echo "------------------------------------------------"\n\
echo "🚀 SERVER ROOT:8 ĐÃ SẴN SÀNG"\n\
echo "📡 SSH: Cổng 22 | Web: Cổng 8080"\n\
echo "------------------------------------------------"\n\
\n\
# VÒNG LẶP KIỂM TRA SỰ SỐNG\n\
while true; do\n\
    # Kiểm tra SSH còn sống không, nếu chết thì bật lại\n\
    if ! nc -z localhost 22; then\n\
        /usr/sbin/sshd\n\
    fi\n\
    \n\
    # In log để Railway thấy có hoạt động (Traffic giả)\n\
    echo "[ALIVE] $(date) - Server đang chạy tốt."\n\
    sleep 60\n\
done' > /start.sh && chmod +x /start.sh

# Cổng nội bộ
EXPOSE 22 8080

CMD ["/start.sh"]
