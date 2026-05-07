FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài các gói thiết yếu
RUN apt-get update && \
    apt-get install -y wget curl git openssh-server net-tools htop tmux && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài Go 1.24 vào /usr/local (Để không bị lỗi No Space)
RUN wget -q https://go.dev/dl/go1.24.0.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.24.0.linux-amd64.tar.gz && \
    rm go1.24.0.linux-amd64.tar.gz

ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/app/go-workspace
ENV GOCACHE=/app/go-cache
ENV PATH=$PATH:$GOPATH/bin

# 3. Cấu hình SSH chuẩn (Bỏ UsePAM no để tránh lỗi syslogin)
RUN mkdir -p /var/run/sshd && \
    ssh-keygen -A && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

WORKDIR /app

# 4. Script khởi động chỉ chạy mỗi SSH
RUN echo "#!/bin/bash\n\
echo 'root:1' | chpasswd\n\
echo '--- SSH Server đang chạy ---'\n\
# Lệnh này sẽ chạy SSH ở chế độ Foreground, giữ container sống mãi mãi\n\
/usr/sbin/sshd -D -e" > start.sh && chmod +x start.sh

EXPOSE 22

CMD ["./start.sh"]
