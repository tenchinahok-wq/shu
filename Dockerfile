FROM ubuntu:latest

# 1. Cài đặt môi trường sạch
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y openssh-server python3 curl sudo && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cấu hình SSH (Cổng 22)
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo "Port 22" >> /etc/ssh/sshd_config

# 3. Tạo script khởi động với cơ chế Debug và Chống sập
RUN echo '#!/bin/bash\n\
echo "root:8" | chpasswd\n\
\n\
# Khởi động SSH\n\
/usr/sbin/sshd\n\
if [ $? -eq 0 ]; then echo "DEBUG: [OK] SSH Server đã bật tại cổng 22"; else echo "DEBUG: [FAIL] SSH Server lỗi"; fi\n\
\n\
# Khởi động Web Server (Healthcheck) chạy ngầm tại cổng 8080\n\
python3 -m http.server 8080 > /dev/null 2>&1 &\n\
if [ $? -eq 0 ]; then echo "DEBUG: [OK] Web Server đã bật tại cổng 8080"; else echo "DEBUG: [FAIL] Web Server lỗi"; fi\n\
\n\
echo "------------------------------------------------"\n\
echo "🚀 CONTAINER ĐÃ SẴN SÀNG (USER: root | PASS: 8)"\n\
echo "🔗 Dùng TCP Proxy của Railway trỏ vào cổng 22"\n\
echo "🌐 Dùng Healthcheck của Railway trỏ vào cổng 8080"\n\
echo "------------------------------------------------"\n\
\n\
# VÒNG LẶP VÔ TẬN - GIỮ CONTAINER KHÔNG BAO GIỜ DỪNG\n\
while true; do\n\
    # Kiểm tra cổng 22 và 8080 nội bộ để in log debug\n\
    if ! nc -z localhost 22; then echo "DEBUG: SSH Service bị chết, đang khởi động lại..."; /usr/sbin/sshd; fi\n\
    echo "DEBUG: [ALIVE] $(date) - Server vẫn đang hoạt động..."\n\
    sleep 60\n\
done' > /start.sh && chmod +x /start.sh

# Cổng nội bộ
EXPOSE 22 8080

CMD ["/start.sh"]
