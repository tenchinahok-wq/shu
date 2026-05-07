FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y wget curl git python3 openssh-server net-tools htop tmux && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN wget -q https://go.dev/dl/go1.24.0.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.24.0.linux-amd64.tar.gz && \
    rm go1.24.0.linux-amd64.tar.gz

ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/app/go-workspace
ENV GOCACHE=/app/go-cache
ENV PATH=$PATH:$GOPATH/bin

# Fix phân quyền thư mục SSH (Tránh lỗi SSH tự sập)
RUN mkdir -p /var/run/sshd /run/sshd && \
    chmod 0755 /var/run/sshd /run/sshd && \
    ssh-keygen -A && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

WORKDIR /app

# Web Health Check
RUN echo "from http.server import BaseHTTPRequestHandler, HTTPServer\n\
class HealthCheck(BaseHTTPRequestHandler):\n\
    def do_GET(self):\n\
        self.send_response(200)\n\
        self.end_headers()\n\
        self.wfile.write(b'OK - CONTAINER IS ALIVE')\n\
    def log_message(self, format, *args): return\n\
httpd = HTTPServer(('0.0.0.0', 8080), HealthCheck)\n\
httpd.serve_forever()" > health.py

# Script khởi động: Bắt lỗi SSH trực tiếp
RUN echo "#!/bin/bash\n\
echo 'root:1' | chpasswd\n\
# Bật web ngầm để qua ải kiểm tra của Railway\n\
python3 health.py &\n\
echo '--- Đang khởi động SSH Server ---'\n\
# Ép SSH in mọi lỗi ra màn hình Railway Logs (-e) và chạy chính diện (-D)\n\
/usr/sbin/sshd -D -e" > start.sh && chmod +x start.sh

EXPOSE 8080 22

CMD ["./start.sh"]
