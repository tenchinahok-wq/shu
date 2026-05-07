FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt các gói nền tảng
RUN apt-get update && \
    apt-get install -y wget curl git python3 python3-pip nodejs npm \
    neofetch vim nano htop build-essential openssh-server net-tools && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài Go 1.24 thủ công vào hệ thống chính (Tránh lỗi "No space" ở /root)
RUN wget https://go.dev/dl/go1.24.0.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.24.0.linux-amd64.tar.gz && \
    rm go1.24.0.linux-amd64.tar.gz

ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/app/go-workspace
ENV GOCACHE=/app/go-cache
ENV PATH=$PATH:$GOPATH/bin

# 3. Cấu hình SSH Server (Fix lỗi "Connection Closed")
RUN mkdir -p /var/run/sshd && \
    ssh-keygen -A && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

# 4. Cài ttyd (Web Terminal)
RUN wget -qO /bin/ttyd https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 && \
    chmod +x /bin/ttyd

# 5. Thiết lập thư mục làm việc khổng lồ
WORKDIR /app
RUN echo "neofetch" >> /root/.bashrc && \
    echo "cd /app" >> /root/.bashrc

# Mở cổng cho Web (8080) và SSH (22)
EXPOSE 8080 22

CMD ["/bin/bash", "-c", "\
    # Đặt mật khẩu root là 1
    echo 'root:1' | chpasswd && \
    # Khởi động SSH ngầm
    /usr/sbin/sshd && \
    # Chạy ttyd - bỏ cờ -c nếu bạn muốn vào thẳng không cần login
    # Nếu muốn an toàn, dùng: /bin/ttyd -p ${PORT:-8080} -c root:1 /bin/bash
    /bin/ttyd -p ${PORT:-8080} /bin/bash"]
