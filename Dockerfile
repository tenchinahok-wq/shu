# Giai đoạn 1: Build nhị phân Go
FROM golang:1.22-bookworm AS builder

WORKDIR /app

# Khởi tạo module và cài đặt thư viện telebot v3
RUN go mod init tele-ssh-bot && \
    go get gopkg.in/telebot.v3

# Tạo mã nguồn main.go (Đã fix lỗi Types)
RUN cat <<'EOF' > main.go
package main

import (
	"bufio"
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"gopkg.in/telebot.v3"
)

type BotState struct {
	mu         sync.Mutex
	CancelFunc context.CancelFunc
	LastMsgID  int
	Lines      []string
	CurrentCmd string
	IsRunning  bool
}

var (
	token      = os.Getenv("TK")
	adminID, _ = strconv.ParseInt(os.Getenv("ID"), 10, 64)
	state      = &BotState{}
)

func main() {
	if token == "" || adminID == 0 {
		log.Fatal("LỖI: Thiếu biến môi trường TK hoặc ID!")
	}

	b, err := telebot.NewBot(telebot.Settings{
		Token:  token,
		Poller: &telebot.LongPoller{Timeout: 10 * time.Second},
	})
	if err != nil {
		log.Fatal(err)
	}

	// Middleware kiểm tra ID người gửi
	b.Use(func(next telebot.HandlerFunc) telebot.HandlerFunc {
		return func(c telebot.Context) error {
			if c.Sender().ID != adminID {
				return nil
			}
			return next(c)
		}
	})

	// Khởi tạo menu và nút bấm
	selector := &telebot.ReplyMarkup{}
	stopBtn := selector.Data("⛔ DỪNG LỆNH (GO MODE)", "stop_cmd")
	selector.Inline(selector.Row(stopBtn))

	// Xử lý nút Dừng
	b.Handle(&stopBtn, func(c telebot.Context) error {
		state.mu.Lock()
		defer state.mu.Unlock()
		if state.CancelFunc != nil && state.IsRunning {
			state.CancelFunc()
			state.IsRunning = false
			return c.Edit("🛑 **Đã gửi tín hiệu KILL sạch tiến trình!**", telebot.ModeMarkdown)
		}
		return c.Respond(&telebot.CallbackResponse{Text: "Không có lệnh nào đang chạy!"})
	})

	// Xử lý Lệnh SSH
	b.Handle(telebot.OnText, func(c telebot.Context) error {
		state.mu.Lock()
		if state.IsRunning && state.CancelFunc != nil {
			state.CancelFunc() // Tự động dừng lệnh cũ
		}
		state.mu.Unlock()

		cmdStr := c.Text()
		chat := c.Chat()

		// Gửi tin nhắn log ban đầu
		msg, _ := b.Send(chat, fmt.Sprintf("🚀 **Exec:** `%s`\n\n`Đang chuẩn bị luồng...`", cmdStr), telebot.ModeMarkdown, selector)

		state.mu.Lock()
		state.LastMsgID = msg.ID
		state.Lines = []string{}
		state.CurrentCmd = cmdStr
		state.IsRunning = true
		state.mu.Unlock()

		ctx, cancel := context.WithCancel(context.Background())
		state.mu.Lock()
		state.CancelFunc = cancel
		state.mu.Unlock()

		go func() {
			defer cancel()
			
			// Sử dụng stdbuf để xuất log ngay lập tức
			shellCmd := exec.CommandContext(ctx, "sh", "-c", "stdbuf -i0 -oL -eL "+cmdStr)
			shellCmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true} // Tạo Group ID để kill cả nhóm

			stdout, _ := shellCmd.StdoutPipe()
			shellCmd.Stderr = shellCmd.Stdout
			
			if err := shellCmd.Start(); err != nil {
				b.Edit(msg, fmt.Sprintf("❌ Lỗi: %v", err))
				return
			}

			reader := bufio.NewReader(stdout)
			done := make(chan bool)
			
			// Luồng đọc log
			go func() {
				for {
					line, err := reader.ReadString('\n')
					if err != nil {
						done <- true
						return
					}
					state.mu.Lock()
					state.Lines = append(state.Lines, strings.TrimSpace(line))
					if len(state.Lines) > 10 {
						state.Lines = state.Lines[1:]
					}
					state.mu.Unlock()
				}
			}()

			ticker := time.NewTicker(1200 * time.Millisecond)
			defer ticker.Stop()
			lastContent := ""

			for {
				select {
				case <-ctx.Done():
					// Gửi SIGKILL vào Group ID (dấu trừ trước PID)
					syscall.Kill(-shellCmd.Process.Pid, syscall.SIGKILL)
					goto final
				case <-done:
					goto final
				case <-ticker.C:
					state.mu.Lock()
					if len(state.Lines) > 0 {
						content := strings.Join(state.Lines, "\n")
						if content != lastContent {
							b.Edit(msg, fmt.Sprintf("🚀 **Running:** `%s`\n\n```text\n%s\n```", cmdStr, content), telebot.ModeMarkdown, selector)
							lastContent = content
						}
					}
					state.mu.Unlock()
				}
			}

		final:
			shellCmd.Wait()
			state.mu.Lock()
			state.IsRunning = false
			status := "✅ Hoàn thành"
			if ctx.Err() != nil {
				status = "🛑 Đã dừng"
			}
			finalLog := strings.Join(state.Lines, "\n")
			b.Edit(msg, fmt.Sprintf("**%s:** `%s`\n\n```text\n%s\n```", status, cmdStr, finalLog), telebot.ModeMarkdown)
			state.mu.Unlock()
		}()

		return nil
	})

	// Xử lý nhận file
	b.Handle(telebot.OnDocument, func(c telebot.Context) error {
		doc := c.Message().Document
		err := b.Download(&doc.File, doc.FileName)
		if err != nil {
			return c.Reply("❌ Lỗi tải file: " + err.Error())
		}
		return c.Reply(fmt.Sprintf("📥 Đã tải file: `%s`", doc.FileName), telebot.ModeMarkdown)
	})

	fmt.Printf("Bot Go SSH đang chạy cho ID: %d\n", adminID)
	b.Start()
}
EOF

# Thực hiện build
RUN go build -o bot main.go

# Giai đoạn 2: Ubuntu Runtime
FROM ubuntu:24.04

# Cài đặt công cụ hệ thống cần thiết cho lệnh SSH
RUN apt-get update && apt-get install -y \
    ca-certificates coreutils curl wget git htop \
    iputils-ping dnsutils net-tools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy file thực thi từ builder
COPY --from=builder /app/bot .

# Khởi chạy bot
CMD ["./bot"]
