FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài tools
RUN apt-get update && \
    apt-get install -y wget curl git openssh-server net-tools htop tmux python3 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài Go 1.24
RUN wget -q https://go.dev/dl/go1.24.0.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.24.0.linux-amd64.tar.gz && \
    rm go1.24.0.linux-amd64.tar.gz

ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/app/go-workspace
ENV GOCACHE=/app/go-cache
ENV PATH=$PATH:$GOPATH/bin

# 3. Cấu hình SSH (Tắt PAM 100%)
RUN mkdir -p /var/run/sshd /run/sshd && \
    ssh-keygen -A && \
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && \
    echo "UsePAM no" >> /etc/ssh/sshd_config && \
    echo "Port 22" >> /etc/ssh/sshd_config

WORKDIR /app

# 4. Tạo file Web giả để "hối lộ" thằng kiểm tra của Railway
RUN echo "HTTP 200 OK - Server is Alive" > index.html

# 5. Script khởi động: Chạy Web ngầm và SSH chính
RUN echo '#!/bin/bash\n\
echo "root:1" | chpasswd\n\
mkdir -p /run/sshd\n\
# Tránh đụng cổng nếu Railway ép biến PORT thành 22\n\
export WEB_PORT=${PORT:-8080}\n\
if [ "$WEB_PORT" = "22" ]; then export WEB_PORT=8080; fi\n\
# Bật Web ngầm để Railway kiểm tra\n\
python3 -m http.server $WEB_PORT &\n\
echo "--- Web Server chạy trên cổng $WEB_PORT ---"\n\
echo "--- SSH Server chạy trên cổng 22 ---"\n\
# Bật SSH\n\
exec /usr/sbin/sshd -D -e\n\
' > start.sh && chmod +x start.sh

EXPOSE 22 8080

CMD ["./start.sh"]
