FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt các gói cần thiết
RUN apt-get update && \
    apt-get install -y wget curl git python3 openssh-server net-tools htop tmux && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài Go 1.24 vào phân vùng lớn (Tránh lỗi No Space)
RUN wget https://go.dev/dl/go1.24.0.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.24.0.linux-amd64.tar.gz && \
    rm go1.24.0.linux-amd64.tar.gz

ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/app/go-workspace
ENV GOCACHE=/app/go-cache
ENV PATH=$PATH:$GOPATH/bin

# 3. Cấu hình SSH
RUN mkdir -p /var/run/sshd && \
    ssh-keygen -A && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

# Chuyển sang thư mục /app (Phân vùng 951GB)
WORKDIR /app

# 4. Tạo file index.html "mồi" để chắc chắn trả về 200 OK
RUN echo "<html><body><h1>Railway Container is Healthy</h1></body></html>" > index.html

EXPOSE 8080 22

CMD ["/bin/bash", "-c", "\
    # Set mật khẩu
    echo 'root:1' | chpasswd && \
    \
    # Chạy SSH server
    /usr/sbin/sshd && \
    \
    # Chạy web server giả ở cổng 8080. 
    # File index.html vừa tạo sẽ đảm bảo Railway nhận được mã 200 OK.
    python3 -m http.server 8080 & \
    \
    echo 'Container is alive. SSH on port 22, Health Check on port 8080'; \
    \
    # Giữ container sống mãi mãi
    tail -f /dev/null"]
