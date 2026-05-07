# Giai đoạn 1: Build nhị phân Go
FROM golang:1.22-bookworm AS builder

WORKDIR /app

# Khởi tạo module và cài đặt telebot v3
RUN go mod init tele-ssh-bot && \
    go get gopkg.in/telebot.v3

# Tạo mã nguồn main.go (Cơ chế Live Update + Nuclear Kill)
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

type ProcessInfo struct {
	Ctx        context.Context
	Cancel     context.CancelFunc
	Command    string
	Lines      []string
	PID        int
	mu         sync.Mutex
	LastUpdate time.Time
}

var (
	token      = os.Getenv("TK")
	adminID, _ = strconv.ParseInt(os.Getenv("ID"), 10, 64)
	activeProcs sync.Map // Map[int]*ProcessInfo (msgID -> Info)
)

func main() {
	if token == "" || adminID == 0 {
		log.Fatal("LỖI: Thiếu biến TK hoặc ID trên Railway!")
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

	// Xử lý nút dừng (Stop callback)
	b.Handle(telebot.OnCallback, func(c telebot.Context) error {
		data := c.Callback().Data
		if strings.HasPrefix(data, "stop_") {
			msgID, _ := strconv.Atoi(strings.TrimPrefix(data, "stop_"))
			if val, ok := activeProcs.Load(msgID); ok {
				p := val.(*ProcessInfo)
				p.mu.Lock()
				if p.PID != 0 {
					// NUCLEAR KILL: Giết cả group tiến trình
					syscall.Kill(-p.PID, syscall.SIGKILL)
				}
				p.mu.Unlock()
				p.Cancel()
				activeProcs.Delete(msgID)
				b.Edit(c.Message(), fmt.Sprintf("🛑 **Đã ép dừng:** `%s`", p.Command), telebot.ModeMarkdown)
				return c.Respond(&telebot.CallbackResponse{Text: "Đã dừng ngay lập tức!"})
			}
		}
		return c.Respond(&telebot.CallbackResponse{Text: "Lệnh không còn tồn tại."})
	})

	// Xử lý lệnh văn bản
	b.Handle(telebot.OnText, func(c telebot.Context) error {
		cmdStr := c.Text()
		chat := c.Chat()

		// Gửi tin nhắn khởi tạo
		msg, _ := b.Send(chat, fmt.Sprintf("🚀 **Exec:** `%s`\n\n`Đang chuẩn bị...`", cmdStr), telebot.ModeMarkdown)
		
		// Tạo nút dừng riêng cho tin nhắn này
		selector := &telebot.ReplyMarkup{}
		stopBtn := selector.Data("⛔ DỪNG LỆNH NÀY", "stop_"+strconv.Itoa(msg.ID))
		selector.Inline(selector.Row(stopBtn))
		
		// Cập nhật để hiện nút bấm
		b.Edit(msg, fmt.Sprintf("🚀 **Exec:** `%s`\n\n`Luồng dữ liệu đã sẵn sàng...`", cmdStr), telebot.ModeMarkdown, selector)

		ctx, cancel := context.WithCancel(context.Background())
		pInfo := &ProcessInfo{
			Ctx:     ctx,
			Cancel:  cancel,
			Command: cmdStr,
			Lines:   []string{},
		}
		activeProcs.Store(msg.ID, pInfo)

		go func() {
			defer cancel()
			defer activeProcs.Delete(msg.ID)

			// Khởi chạy với stdbuf để xóa buffer hệ thống
			shellCmd := exec.CommandContext(ctx, "sh", "-c", "stdbuf -i0 -oL -eL "+cmdStr)
			shellCmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

			stdout, _ := shellCmd.StdoutPipe()
			shellCmd.Stderr = shellCmd.Stdout
			
			if err := shellCmd.Start(); err != nil {
				b.Edit(msg, "❌ Lỗi: "+err.Error())
				return
			}

			pInfo.mu.Lock()
			pInfo.PID = shellCmd.Process.Pid
			pInfo.mu.Unlock()

			// Kênh thông báo có dòng log mới
			logChan := make(chan string, 100)

			// Goroutine đọc log từ Pipe
			go func() {
				scanner := bufio.NewScanner(stdout)
				for scanner.Scan() {
					txt := scanner.Text()
					if txt != "" {
						logChan <- txt
					}
				}
			}()

			ticker := time.NewTicker(1200 * time.Millisecond)
			defer ticker.Stop()

			firstLineReceived := false

			for {
				select {
				case <-ctx.Done():
					// Kill khi nhận tín hiệu cancel
					pInfo.mu.Lock()
					if pInfo.PID != 0 {
						syscall.Kill(-pInfo.PID, syscall.SIGKILL)
					}
					pInfo.mu.Unlock()
					goto final
				case line := <-logChan:
					pInfo.mu.Lock()
					pInfo.Lines = append(pInfo.Lines, line)
					if len(pInfo.Lines) > 10 {
						pInfo.Lines = pInfo.Lines[1:]
					}
					
					// NẾU LÀ DÒNG ĐẦU TIÊN: Cập nhật ngay lập tức không đợi ticker
					if !firstLineReceived {
						firstLineReceived = true
						content := strings.Join(pInfo.Lines, "\n")
						b.Edit(msg, fmt.Sprintf("🚀 **Running:** `%s`\n\n```text\n%s\n```", cmdStr, content), telebot.ModeMarkdown, selector)
						pInfo.LastUpdate = time.Now()
					}
					pInfo.mu.Unlock()

				case <-ticker.C:
					// Cập nhật định kỳ để tránh rate limit
					pInfo.mu.Lock()
					if len(pInfo.Lines) > 0 && time.Since(pInfo.LastUpdate) >= 1100*time.Millisecond {
						content := strings.Join(pInfo.Lines, "\n")
						b.Edit(msg, fmt.Sprintf("🚀 **Running:** `%s`\n\n```text\n%s\n```", cmdStr, content), telebot.ModeMarkdown, selector)
						pInfo.LastUpdate = time.Now()
					}
					pInfo.mu.Unlock()
					
					if shellCmd.ProcessState != nil {
						goto final
					}
				case <-time.After(500 * time.Millisecond):
					// Check thoát tiến trình
					if shellCmd.ProcessState != nil {
						goto final
					}
				}
			}

		final:
			shellCmd.Wait()
			pInfo.mu.Lock()
			status := "✅ Hoàn thành"
			if ctx.Err() != nil {
				status = "🛑 Đã dừng"
			}
			res := strings.Join(pInfo.Lines, "\n")
			b.Edit(msg, fmt.Sprintf("**%s:** `%s`\n\n```text\n%s\n```", status, cmdStr, res), telebot.ModeMarkdown)
			pInfo.mu.Unlock()
		}()

		return nil
	})

	// Xử lý nhận file
	b.Handle(telebot.OnDocument, func(c telebot.Context) error {
		doc := c.Message().Document
		if err := b.Download(&doc.File, doc.FileName); err != nil {
			return c.Reply("❌ Lỗi tải file: " + err.Error())
		}
		return c.Reply(fmt.Sprintf("📥 Đã tải file: `%s`", doc.FileName), telebot.ModeMarkdown)
	})

	fmt.Printf("Bot Go SSH Ultra Live đang chạy cho ID: %d\n", adminID)
	b.Start()
}
EOF

RUN go build -o bot main.go

# Giai đoạn 2: Runtime Ubuntu 24.04
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    ca-certificates coreutils curl wget git htop \
    iputils-ping dnsutils net-tools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/bot .

# Khởi chạy bot
CMD ["./bot"]
