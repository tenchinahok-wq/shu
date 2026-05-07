FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt các gói cần thiết
RUN apt-get update && \
    apt-get install -y wget curl git python3 openssh-server net-tools htop tmux && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài Go 1.24 vào phân vùng /usr/local (951GB)
RUN wget -q https://go.dev/dl/go1.24.0.linux-amd64.tar.gz && \
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

# 4. TẠO FILE HEALTH CHECK RIÊNG (Để tránh lỗi dấu ngoặc trong CMD)
RUN echo "from http.server import BaseHTTPRequestHandler, HTTPServer\n\
import os\n\
class HealthCheck(BaseHTTPRequestHandler):\n\
    def do_GET(self):\n\
        self.send_response(200)\n\
        self.end_headers()\n\
        self.wfile.write(b'OK')\n\
    def log_message(self, format, *args): return\n\
port = int(os.environ.get('PORT', 8080))\n\
httpd = HTTPServer(('0.0.0.0', port), HealthCheck)\n\
print(f'Health Check running on port {port}')\n\
httpd.serve_forever()" > /app/health_check.py

WORKDIR /app
EXPOSE 8080 22

# 5. CMD đơn giản, không bị lỗi dấu ngoặc
CMD ["/bin/bash", "-c", "echo 'root:1' | chpasswd && /usr/sbin/sshd && python3 /app/health_check.py"]
