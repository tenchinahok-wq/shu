FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt tools
RUN apt-get update && \
    apt-get install -y wget curl git python3 openssh-server net-tools htop tmux && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài Go 1.24
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

# 4. CHÌA KHÓA Ở ĐÂY: Tạo và chuyển vào thư mục /app TRƯỚC TIÊN
WORKDIR /app

# 5. Giờ thì ghi file thoải mái không bao giờ lỗi "Directory nonexistent"
RUN echo "from http.server import BaseHTTPRequestHandler, HTTPServer\n\
class HealthCheck(BaseHTTPRequestHandler):\n\
    def do_GET(self):\n\
        self.send_response(200)\n\
        self.end_headers()\n\
        self.wfile.write(b'OK - CONTAINER IS ALIVE')\n\
    def log_message(self, format, *args): return\n\
httpd = HTTPServer(('0.0.0.0', 8080), HealthCheck)\n\
print('--- Health Check Server started on port 8080 ---')\n\
httpd.serve_forever()" > health.py

# 6. Tạo script khởi động
RUN echo "#!/bin/bash\n\
echo 'root:1' | chpasswd\n\
/usr/sbin/sshd\n\
echo '--- SSH Server started on port 22 ---'\n\
python3 health.py" > start.sh && chmod +x start.sh

EXPOSE 8080 22

CMD ["./start.sh"]
