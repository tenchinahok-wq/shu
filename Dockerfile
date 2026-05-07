FROM ubuntu:24.04

# Ngăn các thông báo tương tác
ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt các gói cần thiết
RUN apt-get update && \
    apt-get install -y wget curl git python3 openssh-server net-tools htop tmux && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài Go 1.24 vào /usr/local (Phân vùng 951GB)
RUN echo "--- Đang cài đặt Go 1.24 ---" && \
    wget -q https://go.dev/dl/go1.24.0.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.24.0.linux-amd64.tar.gz && \
    rm go1.24.0.linux-amd64.tar.gz

# Cấu hình môi trường Go
ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/app/go-workspace
ENV GOCACHE=/app/go-cache
ENV PATH=$PATH:$GOPATH/bin

# 3. Cấu hình SSH chuẩn
RUN mkdir -p /var/run/sshd && \
    ssh-keygen -A && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config && \
    echo "Port 22" >> /etc/ssh/sshd_config

# 4. Thiết lập thư mục làm việc lớn
WORKDIR /app
RUN mkdir -p /app/go-workspace /app/go-cache

EXPOSE 8080 22

# 5. CMD với đầy đủ Log Debug
CMD ["/bin/bash", "-c", "\
    echo '[DEBUG] Bắt đầu khởi tạo Container...'; \
    \
    # Thiết lập mật khẩu
    echo 'root:1' | chpasswd && \
    echo '[DEBUG] Đã thiết lập mật khẩu root:1'; \
    \
    # Khởi động SSH
    /usr/sbin/sshd -D & \
    echo '[DEBUG] SSH Server đang chạy trên port 22'; \
    \
    # Server Health Check 'Vạn năng' - Luôn trả về 200 OK
    echo '[DEBUG] Đang khởi động Health Check trên port ${PORT:-8080}...'; \
    python3 -u -c \"from http.server import BaseHTTPRequestHandler, HTTPServer; \
class HealthCheck(BaseHTTPRequestHandler): \
    def do_GET(self): \
        self.send_response(200); \
        self.end_headers(); \
        self.wfile.write(b'HEALTHY - 200 OK'); \
        print(f'[LOG] Health Check từ {self.client_address} - Thành công'); \
    def log_message(self, format, *args): return; \
httpd = HTTPServer(('0.0.0.0', int('${PORT:-8080}')), HealthCheck); \
httpd.serve_forever()\" & \
    \
    echo '[DEBUG] Hệ thống đã sẵn sàng!'; \
    \
    # Giữ container sống và in log hệ thống
    tail -f /dev/null\"]
