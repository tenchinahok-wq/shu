# Giai đoạn 1: Build
FROM golang:1.22-bookworm AS builder
WORKDIR /app
COPY . .
RUN go mod init telegram-exec-bot && \
    go get gopkg.in/telebot.v3 && \
    go build -o bot main.go

# Giai đoạn 2: Runtime
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y \
    ca-certificates coreutils curl wget git htop iputils-ping dnsutils net-tools \
    && apt-get clean

WORKDIR /app
COPY --from=builder /app/bot .
CMD ["./bot"]
