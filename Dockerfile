FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# 1. Cài các gói thiết yếu
RUN apt-get update && \
    apt-get install -y wget curl git openssh-server net-tools htop tmux && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Cài Go 1.24 vào /usr/local (Ngon lành, không lo No Space)
RUN wget -q https://go.dev/dl/go1.24.0.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.24.0.linux-amd64.tar.gz && \
    rm go1.24.0.linux-amd64.tar.gz

ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/app/go-workspace
ENV GOCACHE=/app/go-cache
ENV PATH=$PATH:$GOPATH/bin

# 3. Cấu hình SSH + Fix lỗi trắng màn (PAM)
RUN ssh-keygen -A && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd

WORKDIR /app

# 4. XÂY DỰNG SCRIPT KHỞI ĐỘNG "BẤT TỬ" (Ghi từng dòng cực kỳ an toàn)
RUN echo '#!/bin/bash' > start.sh && \
    echo 'echo "root:1" | chpasswd' >> start.sh && \
    # Khắc phục lỗi Docker tự xóa thư mục
    echo 'mkdir -p /run/sshd' >> start.sh && \
    # Ép SSH mở cổng 22
    echo 'echo "Port 22" >> /etc/ssh/sshd_config' >> start.sh && \
    # Ép SSH mở luôn cổng PORT của Railway để nó tự kiểm tra sức khỏe
    echo 'echo "Port ${PORT:-8080}" >> /etc/ssh/sshd_config' >> start.sh && \
    echo 'echo "--- SSH Server đang chạy ---"' >> start.sh && \
    # Ép tiến trình SSH chạy trực diện (-D) và in hết log ra màn hình (-e)
    echo 'exec /usr/sbin/sshd -D -e' >> start.sh && \
    chmod +x start.sh

EXPOSE 22

CMD ["./start.sh"]
