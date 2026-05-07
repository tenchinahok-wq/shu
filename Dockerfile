FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài các gói thiết yếu
RUN apt-get update && \
    apt-get install -y wget curl git openssh-server net-tools htop tmux && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài Go 1.24 vào /usr/local
RUN wget -q https://go.dev/dl/go1.24.0.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.24.0.linux-amd64.tar.gz && \
    rm go1.24.0.linux-amd64.tar.gz

ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/app/go-workspace
ENV GOCACHE=/app/go-cache
ENV PATH=$PATH:$GOPATH/bin

# 3. Cấu hình SSH và FIX LỖI PAM (Chống trắng màn)
RUN mkdir -p /var/run/sshd /run/sshd && \
    ssh-keygen -A && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    # CHÌA KHÓA Ở ĐÂY: Vô hiệu hóa việc ép buộc ghi log của PAM trong Docker
    sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd

WORKDIR /app

# 4. Script khởi động: Chạy SSH ngầm và giữ container luôn sống
RUN echo "#!/bin/bash\n\
echo 'root:1' | chpasswd\n\
# Khởi động SSH server ngầm\n\
/usr/sbin/sshd\n\
echo '--- SSH Server đang chạy, sẵn sàng kết nối ---'\n\
# Giữ container sống vĩnh viễn dù bác có thoát SSH\n\
tail -f /dev/null" > start.sh && chmod +x start.sh

EXPOSE 22

CMD ["./start.sh"]
