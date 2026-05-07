FROM ubuntu:24.04

# Ngăn các câu hỏi tương tác khi cài đặt
ARG DEBIAN_FRONTEND=noninteractive

# Cài đặt các công cụ cơ bản + lrzsz (để upload/download file qua terminal)
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
    wget curl git python3 python3-pip nodejs npm \
    neofetch vim nano htop build-essential \
    lrzsz zip unzip tmux \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Cài đặt ttyd (bản mới nhất hỗ trợ tốt hơn cho mobile)
RUN wget -qO /bin/ttyd https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 && \
    chmod +x /bin/ttyd

# Cấu hình shell cho đẹp và tiện dụng
RUN echo "neofetch" >> /root/.bashrc && \
    echo "alias ll='ls -alF'" >> /root/.bashrc && \
    echo "export PS1='\[\033[01;32m\]\u@web-ssh\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '" >> /root/.bashrc

# Workspace mặc định
WORKDIR /root

# Cổng mặc định cho Railway hoặc local
EXPOSE 8080

# Chạy ttyd với cấu hình tối ưu cho Mobile
# -t fontSize=14: Kích thước chữ vừa đủ nhìn trên điện thoại
# -t enableZmodem=true: Cho phép dùng lệnh rz/sz để truyền file
# -t cursorBlink=true: Nhấp nháy con trỏ để dễ tìm trên màn hình nhỏ
CMD ["/bin/bash", "-c", "/bin/ttyd \
    -p ${PORT:-8080} \
    -c ${USERNAME:-admin}:${PASSWORD:-123456} \
    -t fontSize=14 \
    -t fontFamily='Monaco, monospace' \
    -t enableZmodem=true \
    -t enableTriggers=true \
    -t cursorBlink=true \
    /bin/bash"]
