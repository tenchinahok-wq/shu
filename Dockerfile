FROM ubuntu:24.04

# Build-time only - prevents interactive prompts
ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt các gói cơ bản, SSH, NodeJS, Golang
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y wget curl git python3 python3-pip nodejs npm \
    neofetch vim nano htop build-essential openssh-server sudo dos2unix iptables && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài đặt Golang 1.22.2 (Sẵn sàng cho dev)
RUN wget https://go.dev/dl/go1.22.2.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.22.2.linux-amd64.tar.gz && rm go1.22.2.linux-amd64.tar.gz
ENV PATH=$PATH:/usr/local/go/bin

# 3. Cài đặt ttyd (Web Terminal)
RUN wget -qO /bin/ttyd https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 && \
    chmod +x /bin/ttyd

# 4. Cài đặt Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# 5. Cấu hình SSH & Tài khoản shopee (Quyền cao nhất)
RUN useradd -m -s /bin/bash shopee && echo "shopee:shopee" | chpasswd && adduser shopee sudo && \
    echo "shopee ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    mkdir /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# 6. Thiết lập bash và neofetch
RUN echo "neofetch" >> /root/.bashrc && \
    echo "neofetch" >> /home/shopee/.bashrc

# 7. Copy script khởi động
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN dos2unix /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

# Railway sẽ gán PORT tự động
EXPOSE 8080 22

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
