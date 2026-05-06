FROM ubuntu:22.04

# Xóa user mặc định nếu có để tránh xung đột UID
RUN userdel -r ubuntu 2>/dev/null || true

# Cài đặt SSH Server và các công cụ network cơ bản
RUN apt-get update && apt-get install -y \
    openssh-server \
    sudo \
    iproute2 \
    iputils-ping \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Tạo thư mục chạy cho sshd
RUN mkdir -p /run/sshd && chmod 755 /run/sshd

# Cấu hình SSH: Cho phép Root login và Password (dùng sed để ghi đè chuẩn xác)
RUN sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && echo "TCPKeepAlive yes" >> /etc/ssh/sshd_config

# Copy script cấu hình vào container
COPY ssh-user-config.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/ssh-user-config.sh

EXPOSE 22

# Chạy script cấu hình khi khởi động
CMD ["/usr/local/bin/ssh-user-config.sh"]
