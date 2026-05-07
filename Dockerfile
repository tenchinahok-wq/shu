FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài tools
RUN apt-get update && \
    apt-get install -y wget curl git openssh-server net-tools htop tmux && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài Go 1.24
RUN wget -q https://go.dev/dl/go1.24.0.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.24.0.linux-amd64.tar.gz && \
    rm go1.24.0.linux-amd64.tar.gz

ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/app/go-workspace
ENV GOCACHE=/app/go-cache
ENV PATH=$PATH:$GOPATH/bin

# 3. ÉP CẤU HÌNH SSH (TẮT HẲN PAM ĐỂ KHÔNG BAO GIỜ BỊ ĐÁ RA)
RUN mkdir -p /var/run/sshd /run/sshd && \
    ssh-keygen -A && \
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && \
    echo "UsePAM no" >> /etc/ssh/sshd_config

WORKDIR /app

# 4. Script khởi động cực gọn
RUN echo '#!/bin/bash\n\
echo "root:1" | chpasswd\n\
mkdir -p /run/sshd\n\
echo "--- SSH Server đang chạy ---"\n\
exec /usr/sbin/sshd -D -e\n\
' > start.sh && chmod +x start.sh

EXPOSE 22

CMD ["./start.sh"]
