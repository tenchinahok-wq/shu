# Giai đoạn 1: Build Bot bằng Golang
FROM golang:1.22-bookworm AS builder

WORKDIR /app

# 1. Khởi tạo module và cài đặt telebot v3
RUN go mod init tele-ssh-bot && \
    go get gopkg.in/telebot.v3

# 2. Tạo mã nguồn main.go trực tiếp (Xử lý Live Log, Stop, PTY)
RUN cat <<'EOF' > main.go
package main

import (
	"bufio"
	"context"
	"fmt"
	"io"
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
	mu           sync.Mutex
	CancelFunc   context.CancelFunc
	LastMsgID    int
	Lines        []string
	CurrentCmd   string
	IsRunning    bool
}

var (
	token     = os.Getenv("TK")
	adminID, _ = strconv.ParseInt(os.Getenv("ID"), 10, 64)
	state     = &BotState{}
)

func main() {
	if token == "" || adminID == 0 {
		log.Fatal("LỖI: Chưa cấu hình biến TK hoặc ID!")
	}

	pref := telebot.Settings{
		Token:  token,
		Poller: &telebot.LongPoller{Timeout: 10 * time.Second},
	}

	b, err := telebot.NewBot(pref)
	if err != nil {
		log.Fatal(err)
	}

	// Middleware kiểm tra quyền admin
	b.Use(func(next telebot.HandlerFunc) telebot.HandlerFunc {
		return func(c telebot.Context) error {
			if c.Sender().ID != adminID {
				return nil
			}
			return next(c)
		}
	})

	// Nút dừng lệnh
	stopBtn := telebot.InlineButton{
		Unique: "stop_cmd",
		Text:   "⛔ DỪNG LỆNH NGAY (GO MODE)",
	}

	// Xử lý khi nhấn nút Dừng
	b.Handle(&stopBtn, func(c telebot.Context) error {
		state.mu.Lock()
		defer state.mu.Unlock()
		if state.CancelFunc != nil {
			state.CancelFunc()
			state.IsRunning = false
			return c.Edit("🛑 **Đã gửi tín hiệu giết tiến trình cưỡng bức!**", telebot.ModeMarkdown)
		}
		return c.Respond(&telebot.CallbackResponse{Text: "Không có lệnh nào đang chạy!"})
	})

	// Xử lý tin nhắn văn bản (Lệnh SSH)
	b.Handle(telebot.OnText, func(c telebot.Context) error {
		state.mu.Lock()
		if state.IsRunning {
			if state.CancelFunc != nil {
				state.CancelFunc() // Tự động giết lệnh cũ nếu có lệnh mới
			}
		}
		state.mu.Unlock()

		cmdStr := c.Text()
		
		// Xóa tin nhắn cũ cho sạch chat
		if state.LastMsgID != 0 {
			b.Delete(&telebot.Message{ID: state.LastMsgID, Chat: c.Chat()})
		}

		menu := &telebot.ReplyMarkup{}
		menu.Inline(menu.Row(stopBtn))

		msg, _ := b.Send(c.Chat(), fmt.Sprintf("🚀 **Exec:** `%s`\n\n`Đang chuẩn bị luồng dữ liệu...`", cmdStr), telebot.ModeMarkdown, menu)
		
		state.mu.Lock()
		state.LastMsgID = msg.ID
		state.Lines = []string{}
		state.CurrentCmd = cmdStr
		state.IsRunning = true
		state.mu.Unlock()

		// Chạy lệnh với Context để có thể hủy bỏ
		ctx, cancel := context.WithCancel(context.Background())
		state.mu.Lock()
		state.CancelFunc = cancel
		state.mu.Unlock()

		go func() {
			defer cancel()
			
			// stdbuf -i0 -oL -eL: Ép Linux tắt buffer dòng
			shellCmd := exec.CommandContext(ctx, "sh", "-c", "stdbuf -i0 -oL -eL "+cmdStr)
			shellCmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true} // Tạo group PID để kill sạch con cháu

			stdout, _ := shellCmd.StdoutPipe()
			shellCmd.Stderr = shellCmd.Stdout
			
			if err := shellCmd.Start(); err != nil {
				b.Edit(msg, fmt.Sprintf("❌ Lỗi khởi động: %v", err))
				return
			}

			reader := bufio.NewReader(stdout)
			ticker := time.NewTicker(1200 * time.Millisecond)
			defer ticker.Stop()

			done := make(chan bool)
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

			lastContent := ""
			for {
				select {
				case <-ctx.Done():
					syscall.Kill(-shellCmd.Process.Pid, syscall.SIGKILL) // Kill sạch nhóm tiến trình
					return
				case <-done:
					goto final
				case <-ticker.C:
					state.mu.Lock()
					if len(state.Lines) > 0 {
						content := strings.Join(state.Lines, "\n")
						if content != lastContent {
							newText := fmt.Sprintf("🚀 **Running:** `%s`\n\n```text\n%s\n```", cmdStr, content)
							b.Edit(msg, newText, telebot.ModeMarkdown, menu)
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
			finalContent := strings.Join(state.Lines, "\n")
			status := "✅ Hoàn thành"
			if ctx.Err() != nil {
				status = "🛑 Đã dừng"
			}
			b.Edit(msg, fmt.Sprintf("**%s:** `%s`\n\n```text\n%s\n```", status, cmdStr, finalContent), telebot.ModeMarkdown)
			state.mu.Unlock()
		}()

		return nil
	})

	// Xử lý tải file
	b.Handle(telebot.OnDocument, func(c telebot.Context) error {
		doc := c.Message().Document
		b.Download(doc, doc.FileName)
		return c.Reply(fmt.Sprintf("📥 Đã tải file: `%s`", doc.FileName), telebot.ModeMarkdown)
	})

	fmt.Printf("Bot Go SSH đang chạy cho ID: %d\n", adminID)
	b.Start()
}
EOF

# Compile mã nguồn sang file nhị phân
RUN go build -o bot main.go

# Giai đoạn 2: Runtime (Sử dụng Ubuntu 24.04 cho đầy đủ thư viện)
FROM ubuntu:24.04

# Cài đặt các công cụ hệ thống cần thiết
RUN apt-get update && apt-get install -y \
    ca-certificates coreutils htop curl wget git \
    iputils-ping dnsutils net-tools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy file bot đã build từ stage builder
COPY --from=builder /app/bot .

# Lệnh chạy
CMD ["./bot"]
