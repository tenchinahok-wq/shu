FROM ubuntu:22.04

# Chống treo khi cài đặt
ENV DEBIAN_FRONTEND=noninteractive

# -----------------------------
# 1. Cài đặt Hệ thống & Công cụ (NodeJS, Go, SSH)
# -----------------------------
RUN apt update && apt install -y \
    openssh-server curl wget git unzip sudo python3 \
    build-essential ca-certificates \
    && mkdir /var/run/sshd

# Cài đặt Node.js 20.x
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs

# Cài đặt Golang 1.22.2
RUN wget https://go.dev/dl/go1.22.2.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf go1.22.2.linux-amd64.tar.gz \
    && rm go1.22.2.linux-amd64.tar.gz
ENV PATH=$PATH:/usr/local/go/bin

# Cài đặt Cloudflared
RUN curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
    && dpkg -i cloudflared.deb && rm cloudflared.deb

# -----------------------------
# 2. Cấu hình Tài khoản & Quyền Cao Nhất
# -----------------------------
# Tạo user shopee với pass shopee
RUN useradd -m -s /bin/bash shopee && echo "shopee:shopee" | chpasswd && adduser shopee sudo
# Cấp quyền sudo không cần mật khẩu cho shopee
RUN echo "shopee ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Cho phép Root login và Password Auth
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo "root:shopee" | chpasswd

# -----------------------------
# 3. Khởi chạy
# -----------------------------
COPY start-cloudflare.sh /usr/local/bin/start-cloudflare.sh
RUN chmod +x /usr/local/bin/start-cloudflare.sh

# Expose các port phổ biến
EXPOSE 8080 22 8888 3000

CMD ["/usr/local/bin/start-cloudflare.sh"]
