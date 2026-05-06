FROM ubuntu:22.04

RUN userdel -r ubuntu 2>/dev/null || true

RUN apt-get update && apt-get install -y \
    openssh-server sudo iproute2 python3-minimal \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /run/sshd && chmod 755 /run/sshd && ssh-keygen -A

# Cấu hình SSH chuẩn
RUN sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/^#*UsePAM.*/UsePAM no/' /etc/ssh/sshd_config

COPY ssh-user-config.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/ssh-user-config.sh

# Mở cả 2 cổng
EXPOSE 22
EXPOSE 80

CMD ["/usr/local/bin/ssh-user-config.sh"]
