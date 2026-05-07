# Giai đoạn 1: Build nhị phân Go
FROM golang:1.22-bookworm AS builder

WORKDIR /app

# Khởi tạo module và cài đặt các thư viện cần thiết
RUN go mod init tele-ssh-bot && \
    go get gopkg.in/telebot.v3 && \
    go get github.com/creack/pty

# Tạo mã nguồn main.go
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

	"github.com/creack/pty"
	"gopkg.in/telebot.v3"
)

type ProcessInfo struct {
	Ctx        context.Context
	Cancel     context.CancelFunc
	Command    string
	Lines      []string
	PID        int
	LastUpdate time.Time
	mu         sync.Mutex
}

var (
	token      = os.Getenv("TK")
	adminID, _ = strconv.ParseInt(os.Getenv("ID"), 10, 64)
	// Quản lý đa nhiệm: MsgID -> ProcessInfo
	activeProcs sync.Map 
)

func main() {
	if token == "" || adminID == 0 {
		log.Fatal("LỖI: Cần biến TK và ID!")
	}

	b, err := telebot.NewBot(telebot.Settings{
		Token:  token,
		Poller: &telebot.LongPoller{Timeout: 10 * time.Second},
	})
	if err != nil {
		log.Fatal(err)
	}

	// Middleware bảo mật
	b.Use(func(next telebot.HandlerFunc) telebot.HandlerFunc {
		return func(c telebot.Context) error {
			if c.Sender().ID != adminID {
				return nil
			}
			return next(c)
		}
	})

	// Xử lý nút dừng lệnh (Lệnh nào dừng lệnh đó)
	b.Handle(telebot.OnCallback, func(c telebot.Context) error {
		data := c.Callback().Data
		if strings.HasPrefix(data, "stop_") {
			msgID := strings.TrimPrefix(data, "stop_")
			if val, ok := activeProcs.Load(msgID); ok {
				p := val.(*ProcessInfo)
				p.Cancel() // Hủy context
				if p.PID != 0 {
					// Kill cả nhóm tiến trình
					syscall.Kill(-p.PID, syscall.SIGKILL)
				}
				activeProcs.Delete(msgID)
				b.Edit(c.Message(), fmt.Sprintf("🛑 **Đã dừng lệnh:** `%s`", p.Command), telebot.ModeMarkdown)
				return c.Respond(&telebot.CallbackResponse{Text: "Đã dừng!"})
			}
		}
		return c.Respond(&telebot.CallbackResponse{Text: "Lệnh đã kết thúc hoặc không tìm thấy!"})
	})

	// Xử lý chạy lệnh SSH
	b.Handle(telebot.OnText, func(c telebot.Context) error {
		cmdStr := c.Text()
		
		// Gửi tin nhắn khởi tạo
		msg, err := b.Send(c.Chat(), fmt.Sprintf("🚀 **Exec:** `%s`\n\n`Đang khởi tạo PTY...`", cmdStr), telebot.ModeMarkdown)
		if err != nil {
			return err
		}

		msgIDStr := strconv.Itoa(msg.ID)
		
		// Tạo menu nút dừng riêng cho tin nhắn này
		selector := &telebot.ReplyMarkup{}
		stopBtn := selector.Data("⛔ DỪNG LỆNH NÀY", "stop_"+msgIDStr)
		selector.Inline(selector.Row(stopBtn))
		
		// Cập nhật tin nhắn để có nút bấm
		b.Edit(msg, fmt.Sprintf("🚀 **Exec:** `%s`\n\n`Terminal đã sẵn sàng...`", cmdStr), telebot.ModeMarkdown, selector)

		ctx, cancel := context.WithCancel(context.Background())
		pInfo := &ProcessInfo{
			Ctx:     ctx,
			Cancel:  cancel,
			Command: cmdStr,
			Lines:   []string{},
		}
		activeProcs.Store(msgIDStr, pInfo)

		go func() {
			defer cancel()
			defer activeProcs.Delete(msgIDStr)

			// Khởi chạy lệnh qua PTY để ép log ra ngay tắp lự
			c := exec.CommandContext(ctx, "sh", "-c", cmdStr)
			c.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

			f, err := pty.Start(c)
			if err != nil {
				b.Edit(msg, "❌ Lỗi PTY: "+err.Error())
				return
			}
			defer f.Close()

			pInfo.mu.Lock()
			pInfo.PID = c.Process.Pid
			pInfo.mu.Unlock()

			// Luồng đọc log theo thời gian thực (đọc từng byte/dòng)
			go func() {
				scanner := bufio.NewScanner(f)
				for scanner.Scan() {
					text := scanner.Text()
					if text == "" {
						continue
					}
					pInfo.mu.Lock()
					pInfo.Lines = append(pInfo.Lines, text)
					if len(pInfo.Lines) > 10 {
						pInfo.Lines = pInfo.Lines[1:]
					}
					pInfo.mu.Unlock()
				}
			}()

			ticker := time.NewTicker(1200 * time.Millisecond)
			defer ticker.Stop()
			lastLog := ""

			for {
				select {
				case <-ctx.Done():
					return
				case <-ticker.C:
					pInfo.mu.Lock()
					if len(pInfo.Lines) > 0 {
						currentLog := strings.Join(pInfo.Lines, "\n")
						if currentLog != lastLog {
							b.Edit(msg, fmt.Sprintf("🚀 **Running:** `%s`\n\n```text\n%s\n```", cmdStr, currentLog), telebot.ModeMarkdown, selector)
							lastLog = currentLog
						}
					}
					pInfo.mu.Unlock()
					
					// Kiểm tra nếu tiến trình đã thoát
					if c.ProcessState != nil || c.Wait() == nil {
						goto final
					}
				}
			}

		final:
			pInfo.mu.Lock()
			finalStatus := "✅ Hoàn thành"
			if ctx.Err() != nil {
				finalStatus = "🛑 Đã dừng"
			}
			res := strings.Join(pInfo.Lines, "\n")
			b.Edit(msg, fmt.Sprintf("**%s:** `%s`\n\n```text\n%s\n```", finalStatus, cmdStr, res), telebot.ModeMarkdown)
			pInfo.mu.Unlock()
		}()

		return nil
	})

	// Xử lý tải file
	b.Handle(telebot.OnDocument, func(c telebot.Context) error {
		doc := c.Message().Document
		if err := b.Download(&doc.File, doc.FileName); err != nil {
			return c.Reply("❌ Lỗi: " + err.Error())
		}
		return c.Reply(fmt.Sprintf("📥 Đã tải file: `%s`", doc.FileName), telebot.ModeMarkdown)
	})

	fmt.Printf("Bot Go PTY (Multi-tasking) đang chạy cho ID: %d\n", adminID)
	b.Start()
}
EOF

# Build file nhị phân
RUN go build -o bot main.go

# Giai đoạn 2: Runtime
FROM ubuntu:24.04

# Cài đặt các thư viện hệ thống cần thiết
RUN apt-get update && apt-get install -y \
    ca-certificates coreutils curl wget git htop \
    iputils-ping dnsutils net-tools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/bot .

# Khởi chạy
CMD ["./bot"]
