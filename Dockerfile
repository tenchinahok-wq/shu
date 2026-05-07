FROM ubuntu:24.04

# Build-time only - ngăn các thông báo tương tác
ARG DEBIAN_FRONTEND=noninteractive

# Cài đặt các công cụ cần thiết và OpenSSH Server
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y wget curl git python3 python3-pip nodejs npm neofetch vim nano htop build-essential openssh-server && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Cấu hình SSH để cho phép đăng nhập root qua password
RUN mkdir /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Tải ttyd (Web Terminal)
RUN wget -qO /bin/ttyd https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 && \
    chmod +x /bin/ttyd

# Cấu hình giao diện bash
RUN echo "neofetch" >> /root/.bashrc && \
    echo "cd /root" >> /root/.bashrc && \
    echo "export PS1='\[\033[01;32m\]root@railway\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '" >> /root/.bashrc

# Mở port cho ttyd (8080) và SSH (22)
EXPOSE 8080 22

CMD ["/bin/bash", "-c", "\
    # Set mật khẩu root là shopee
    echo 'root:shopee' | chpasswd && \
    \
    # Khởi động SSH Server ngầm
    /usr/sbin/sshd && \
    \
    # Chạy ttyd với user root và pass shopee
    /bin/ttyd -p ${PORT:-8080} -c root:shopee /bin/bash"]
