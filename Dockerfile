FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt Hệ thống & SSH
RUN apt update && apt install -y \
    openssh-server curl wget git unzip sudo python3 \
    build-essential ca-certificates iptables \
    && mkdir /var/run/sshd

# 2. Cài đặt NodeJS 20.x & Golang 1.22.2
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs
RUN wget https://go.dev/dl/go1.22.2.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf go1.22.2.linux-amd64.tar.gz \
    && rm go1.22.2.linux-amd64.tar.gz
ENV PATH=$PATH:/usr/local/go/bin

# 3. Cài đặt Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# 4. Cấu hình Tài khoản (User: shopee | Pass: shopee)
RUN useradd -m -s /bin/bash shopee && echo "shopee:shopee" | chpasswd && adduser shopee sudo
RUN echo "shopee ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
RUN echo "root:shopee" | chpasswd
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# 5. Script khởi động
COPY start-tailscale.sh /usr/local/bin/start-tailscale.sh
RUN chmod +x /usr/local/bin/start-tailscale.sh

EXPOSE 8080 22
CMD ["/usr/local/bin/start-tailscale.sh"]
