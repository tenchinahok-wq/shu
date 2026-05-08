FROM golang:1.22-bookworm AS builder
WORKDIR /app
COPY main.go .
RUN go mod init bot && \
    go get gopkg.in/telebot.v3 && \
    go build -ldflags="-s -w" -o bot main.go

FROM ubuntu:24.04
RUN apt-get update && apt-get install -y \
    ca-certificates coreutils curl wget git htop iputils-ping dnsutils net-tools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/bot .
CMD ["./bot"]
