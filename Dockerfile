FROM ubuntu:22.04

# Xóa user ubuntu mặc định
RUN userdel -r ubuntu 2>/dev/null || true

# Cài đặt SSH và các gói network
RUN apt-get update && apt-get install -y \
    openssh-server \
    sudo \
    iproute2 \
    iputils-ping \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Tạo thư mục chạy và tạo Host Keys (BẮT BUỘC để không bị EOF)
RUN mkdir -p /run/sshd && chmod 755 /run/sshd && ssh-keygen -A

# Cấu hình SSH tối ưu cho Docker
RUN sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/^#*UsePAM.*/UsePAM no/' /etc/ssh/sshd_config \
    && echo "TCPKeepAlive yes" >> /etc/ssh/sshd_config \
    && echo "ClientAliveInterval 30" >> /etc/ssh/sshd_config \
    && echo "ClientAliveCountMax 5" >> /etc/ssh/sshd_config

# Copy và cấp quyền script
COPY ssh-user-config.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/ssh-user-config.sh

EXPOSE 22

CMD ["/usr/local/bin/ssh-user-config.sh"]
