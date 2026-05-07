FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt các gói (Thêm python3 để làm web server giả)
RUN apt-get update && \
    apt-get install -y wget curl git python3 openssh-server net-tools htop tmux && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài Go 1.24 vào phân vùng lớn
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

WORKDIR /app

# 4. Expose cổng Web và SSH
EXPOSE 8080 22

CMD ["/bin/bash", "-c", "\
    echo 'root:1' | chpasswd && \
    /usr/sbin/sshd && \
    \
    # CHÌA KHÓA Ở ĐÂY: Chạy 1 web server siêu nhẹ ở cổng 8080 để Railway không giết container
    # Railway sẽ ping vào đây, thấy có phản hồi là nó để bạn sống.
    python3 -m http.server 8080 & \
    \
    echo 'SSH ready on port 22 and Health Check ready on port 8080'; \
    \
    # Giữ container luôn chạy
    tail -f /dev/null"]
