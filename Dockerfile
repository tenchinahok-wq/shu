FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt các gói cần thiết (Bỏ ttyd, thêm tmux để giữ script chạy ngầm)
RUN apt-get update && \
    apt-get install -y wget curl git python3 python3-pip openssh-server net-tools htop tmux && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài Go 1.24 vào /usr/local (Phân vùng 951GB trống)
RUN wget https://go.dev/dl/go1.24.0.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.24.0.linux-amd64.tar.gz && \
    rm go1.24.0.linux-amd64.tar.gz

# Cấu hình đường dẫn cho Go và đẩy cache ra khỏi /root để tránh đầy bộ nhớ
ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/app/go-workspace
ENV GOCACHE=/app/go-cache
ENV PATH=$PATH:$GOPATH/bin

# 3. Cấu hình SSH chuẩn
RUN mkdir -p /var/run/sshd && \
    ssh-keygen -A && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

# 4. Chuyển thư mục làm việc sang /app
WORKDIR /app
RUN echo "cd /app" >> /root/.bashrc

EXPOSE 22

# 5. Lệnh khởi động: Set pass, chạy SSH và GIỮ CONTAINER LUÔN SỐNG
CMD ["/bin/bash", "-c", "\
    # Đặt mật khẩu là 1
    echo 'root:1' | chpasswd && \
    \
    # Khởi động SSH server
    /usr/sbin/sshd && \
    \
    echo 'SSH Server is ready on port 22!' && \
    \
    # Lệnh THẦN THÁNH để giữ container không bao giờ bị dừng
    tail -f /dev/null"]
