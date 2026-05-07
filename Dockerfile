FROM ubuntu:latest

# 1. Cài đặt đúng SSH và dọn dẹp
RUN apt-get update && apt-get install -y openssh-server sudo && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cấu hình SSH để cho phép root:8
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo "TCPKeepAlive yes" >> /etc/ssh/sshd_config

# 3. Chạy duy nhất SSH ở tiền cảnh
# -D giúp tiến trình không thoát, giữ Container sống mãi mãi
CMD bash -c "echo 'root:8' | chpasswd && /usr/sbin/sshd -D"

# Chỉ mở cổng 22
EXPOSE 22
