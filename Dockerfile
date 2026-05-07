FROM ubuntu:24.04

# Ngăn các thông báo tương tác
ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt các công cụ, Node.js, NPM và SSH Server
RUN apt-get update && \
    apt-get install -y wget curl git python3 python3-pip nodejs npm \
    neofetch vim nano htop build-essential openssh-server && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài đặt Go 1.24 thủ công (Để tránh lỗi tràn bộ nhớ như ảnh trước)
RUN wget https://go.dev/dl/go1.24.0.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.24.0.linux-amd64.tar.gz && \
    rm go1.24.0.linux-amd64.tar.gz
ENV PATH=$PATH:/usr/local/go/bin

# 3. Cấu hình SSH: Cho phép đăng nhập không mật khẩu
RUN mkdir /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' /etc/ssh/sshd_config && \
    sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

# 4. Cài đặt ttyd (Web Terminal)
RUN wget -qO /bin/ttyd https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 && \
    chmod +x /bin/ttyd

# 5. Cấu hình Bash prompt
RUN echo "neofetch" >> /root/.bashrc && \
    echo "cd /root" >> /root/.bashrc && \
    echo "export PS1='\[\033[01;32m\]root@railway\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '" >> /root/.bashrc

EXPOSE 8080 22

CMD ["/bin/bash", "-c", "\
    # Xóa mật khẩu của root để cho phép đăng nhập trống
    passwd -d root && \
    \
    # Khởi động SSH server ngầm
    /usr/sbin/sshd && \
    \
    # Khởi động ttyd KHÔNG CÓ tham số -c (không mật khẩu)
    /bin/ttyd -p ${PORT:-8080} /bin/bash"]
