FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt các gói cơ bản
RUN apt-get update && \
    apt-get install -y wget curl git python3 openssh-server net-tools htop tmux && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài Go 1.24 vào /usr/local (Để dùng phân vùng overlay 951GB)
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

# 4. TẠO SCRIPT HEALTH CHECK (Để không bao giờ bị 404 hay lỗi dấu ngoặc)
RUN echo "from http.server import BaseHTTPRequestHandler, HTTPServer\n\
class HealthCheck(BaseHTTPRequestHandler):\n\
    def do_GET(self):\n\
        self.send_response(200)\n\
        self.end_headers()\n\
        self.wfile.write(b'OK - CONTAINER IS ALIVE')\n\
    def log_message(self, format, *args): return\n\
httpd = HTTPServer(('0.0.0.0', 8080), HealthCheck)\n\
print('--- Health Check Server started on port 8080 ---')\n\
httpd.serve_forever()" > /app/health.py

# 5. TẠO SCRIPT KHỞI ĐỘNG (ENTRYPOINT)
RUN echo "#!/bin/bash\n\
echo 'root:1' | chpasswd\n\
/usr/sbin/sshd\n\
echo '--- SSH Server started on port 22 ---'\n\
python3 /app/health.py" > /app/start.sh && chmod +x /app/start.sh

WORKDIR /app
EXPOSE 8080 22

# 6. Lệnh chạy cuối cùng (Cực kỳ đơn giản, không lỗi cú pháp)
CMD ["/app/start.sh"]
