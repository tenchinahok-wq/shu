# --- Stage 1: Build binary ---
FROM golang:1.22-bookworm AS builder
WORKDIR /app
COPY . .
RUN go mod init bot-go && go mod tidy
RUN go build -o bot-exec main.go

# --- Stage 2: Runtime ---
FROM ubuntu:24.04

# Cài đặt các công cụ hệ thống như yêu cầu
RUN apt-get update && apt-get install -y \
    ca-certificates \
    coreutils \
    curl \
    wget \
    git \
    htop \
    iputils-ping \
    dnsutils \
    net-tools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/bot-exec .

# Đảm bảo binary có quyền thực thi
RUN chmod +x ./bot-exec

CMD ["./bot-exec"]
