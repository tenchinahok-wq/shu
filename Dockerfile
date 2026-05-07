FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt các gói cơ bản
RUN apt-get update && \
    apt-get install -y wget curl git python3 python3-pip nodejs npm \
    neofetch vim nano htop build-essential openssh-server net-tools && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài Go 1.24 (Dùng phân vùng overlay 951GB)
RUN wget https://go.dev/dl/go1.24.0.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.24.0.linux-amd64.tar.gz && \
    rm go1.24.0.linux-amd64.tar.gz

ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/app/go-workspace
ENV GOCACHE=/app/go-cache
ENV PATH=$PATH:$GOPATH/bin

# 3. Cấu hình SSH đúng cổng 22
RUN mkdir -p /var/run/sshd && \
    ssh-keygen -A && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo "Port 22" >> /etc/ssh/sshd_config

# 4. Cài ttyd
RUN wget -qO /bin/ttyd https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 && \
    chmod +x /bin/ttyd

WORKDIR /app

# 5. Cổng mặc định
EXPOSE 8080 22

CMD ["/bin/bash", "-c", "\
    # Đặt mật khẩu
    echo 'root:1' | chpasswd && \
    \
    # KHỞI ĐỘNG SSH TRƯỚC (Cổng 22)
    /usr/sbin/sshd && \
    \
    # CHẠY TTYD TRÊN CỔNG 8080 (Cổng Web)
    # Đảm bảo ttyd không chiếm cổng 22 của SSH
    /bin/ttyd -p 8080 /bin/bash"]
