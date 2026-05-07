FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# Cài đặt thêm openssh-server và telnetd
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y wget curl git python3 python3-pip nodejs npm neofetch vim nano htop build-essential \
    openssh-server telnetd sudo && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Cấu hình SSH để cho phép Root Login và mật khẩu
RUN mkdir -p /run/sshd && \
    ssh-keygen -A && \
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#*UsePAM.*/UsePAM no/' /etc/ssh/sshd_config

# Tải ttyd
RUN wget -qO /bin/ttyd https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 && \
    chmod +x /bin/ttyd

RUN echo "neofetch" >> /root/.bashrc

# Port 8080 cho Web (Railway sẽ tự map)
EXPOSE 8080
# Port 22 cho SSH
EXPOSE 22

# Lệnh khởi động song song cả SSH và ttyd
CMD ["/bin/bash", "-c", "\
    echo \"root:$PASSWORD\" | chpasswd && \
    /usr/sbin/sshd && \
    echo \"export PS1='\\[\\033[01;32m\\]root@\\h\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ '\" >> /root/.bashrc && \
    /bin/ttyd -p ${PORT:-8080} -c ${USERNAME:-admin}:${PASSWORD:-admin} /bin/bash"]
