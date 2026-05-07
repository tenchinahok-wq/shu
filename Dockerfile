FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài các gói thiết yếu
RUN apt-get update && \
    apt-get install -y wget curl git openssh-server net-tools htop tmux && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài Go 1.24 vào /usr/local
RUN wget -q https://go.dev/dl/go1.24.0.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.24.0.linux-amd64.tar.gz && \
    rm go1.24.0.linux-amd64.tar.gz

ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/app/go-workspace
ENV GOCACHE=/app/go-cache
ENV PATH=$PATH:$GOPATH/bin

# 3. Cấu hình SSH + Fix lỗi trắng màn PAM
RUN ssh-keygen -A && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd

WORKDIR /app

# 4. SCRIPT KHỞI ĐỘNG "BẮT ĐÚNG BỆNH"
RUN echo '#!/bin/bash' > start.sh && \
    echo 'echo "root:1" | chpasswd' >> start.sh && \
    echo 'mkdir -p /run/sshd' >> start.sh && \
    echo 'echo "--- SSH Server đang chạy ---"' >> start.sh && \
    # Ép SSH khởi động và nhận đúng 1 cổng duy nhất từ Railway, tuyệt đối không đụng cổng
    echo 'exec /usr/sbin/sshd -D -e -p ${PORT:-22}' >> start.sh && \
    chmod +x start.sh

EXPOSE 22

CMD ["./start.sh"]
