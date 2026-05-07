FROM ubuntu:22.04

# Chống treo khi cài đặt các gói
ENV DEBIAN_FRONTEND=noninteractive

# -----------------------------
# 1. Cài đặt các gói hệ thống & SSH
# -----------------------------
RUN apt update && apt install -y \
    openssh-server curl wget git unzip sudo python3 \
    build-essential ca-certificates \
    && mkdir /var/run/sshd

# -----------------------------
# 2. Cài đặt Node.js 20.x (LTS)
# -----------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt install -y nodejs

# -----------------------------
# 3. Cài đặt Golang (1.22.2)
# -----------------------------
RUN wget https://go.dev/dl/go1.22.2.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf go1.22.2.linux-amd64.tar.gz \
    && rm go1.22.2.linux-amd64.tar.gz
ENV PATH=$PATH:/usr/local/go/bin

# -----------------------------
# 4. Cài đặt Cloudflared
# -----------------------------
RUN curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
    && dpkg -i cloudflared.deb && rm cloudflared.deb

# -----------------------------
# 5. Cấu hình User & Bảo mật SSH
# -----------------------------
# User: trthaodev | Pass: thaodev@
RUN useradd -m trthaodev && echo "trthaodev:thaodev@" | chpasswd && adduser trthaodev sudo
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config

# -----------------------------
# 6. Chuẩn bị Script khởi động
# -----------------------------
COPY start-cloudflare.sh /usr/local/bin/start-cloudflare.sh
RUN chmod +x /usr/local/bin/start-cloudflare.sh

# Mở các cổng cần thiết
EXPOSE 8080 22 8888 80 443

CMD ["/usr/local/bin/start-cloudflare.sh"]
