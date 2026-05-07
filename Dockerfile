FROM ubuntu:22.04

# 1. Cài đặt sạch
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y openssh-server python3 curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cấu hình SSH
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo "TCPKeepAlive yes" >> /etc/ssh/sshd_config

# 3. Lệnh chạy gộp: Gán pass và bật SSH ở chế độ KHÔNG tắt (D)
# Web server chạy nền để trả lời Railway
CMD bash -c "echo 'root:8' | chpasswd && python3 -m http.server ${PORT:-8080} & /usr/sbin/sshd -D"
