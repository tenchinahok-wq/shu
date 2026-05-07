FROM ubuntu:latest

# 1. Cài đặt sạch và đầy đủ công cụ cứu hộ
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    openssh-server python3 curl sudo net-tools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cấu hình SSH (Cổng 22)
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo "TCPKeepAlive yes" >> /etc/ssh/sshd_config && \
    echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config

# 3. Script khởi động siêu bền
# Mình dùng 'tail -f /dev/null' ở cuối để ép Container sống mãi mãi
RUN echo '#!/bin/bash\n\
echo "root:8" | chpasswd\n\
\n\
# Bật SSH ở chế độ nền\n\
/usr/sbin/sshd\n\
\n\
# Bật Web server ở chế độ nền tại cổng 8080\n\
python3 -m http.server 8080 > /dev/null 2>&1 &\n\
\n\
echo "------------------------------------------------"\n\
echo "🚀 SERVER ROOT:8 ĐÃ LÊN (FIXED VERSION)"\n\
echo "📡 SSH: 22 | Web: 8080"\n\
echo "------------------------------------------------"\n\
\n\
# Lệnh quan trọng nhất: Giữ container không bao giờ thoát\n\
tail -f /dev/null' > /start.sh && chmod +x /start.sh

# Chỉ định rõ cổng
EXPOSE 22 8080

CMD ["/bin/bash", "/start.sh"]
