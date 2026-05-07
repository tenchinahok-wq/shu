# Giai đoạn 1: Build nhị phân Go
FROM golang:1.22-bookworm AS builder

WORKDIR /app

# Khởi tạo module và cài đặt telebot v3
RUN go mod init tele-ssh-bot && \
    go get gopkg.in/telebot.v3

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
	activeProcs sync.Map // Map[int]*ProcessInfo (Key: MessageID)
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

	// Middleware bảo mật: Chỉ Admin mới dùng được
	b.Use(func(next telebot.HandlerFunc) telebot.HandlerFunc {
		return func(c telebot.Context) error {
			if c.Sender().ID != adminID {
				return nil
			}
			return next(c)
		}
	})

	// XỬ LÝ NÚT DỪNG RIÊNG BIỆT
	b.Handle(telebot.OnCallback, func(c telebot.Context) error {
		data := c.Callback().Data
		if strings.HasPrefix(data, "stop_") {
			msgIDStr := strings.TrimPrefix(data, "stop_")
			msgID, _ := strconv.Atoi(msgIDStr)

			if val, ok := activeProcs.Load(msgID); ok {
				p := val.(*ProcessInfo)
				p.mu.Lock()
				if p.PID != 0 {
					// Gửi tín hiệu SIGKILL cho toàn bộ Group ID
					syscall.Kill(-p.PID, syscall.SIGKILL)
				}
				p.mu.Unlock()
				p.Cancel() // Hủy context của goroutine
				
				b.Edit(c.Message(), fmt.Sprintf("🛑 **ĐÃ DỪNG LỆNH:** `%s`", p.Command), telebot.ModeMarkdown)
				return c.Respond(&telebot.CallbackResponse{Text: "Lệnh đã được tiêu diệt!"})
			}
		}
		return c.Respond(&telebot.CallbackResponse{Text: "Lệnh này đã kết thúc từ trước."})
	})

	// XỬ LÝ CHẠY LỆNH (ĐA LUỒNG)
	b.Handle(telebot.OnText, func(c telebot.Context) error {
		cmdStr := c.Text()
		chat := c.Chat()

		// Gửi tin nhắn trạng thái ban đầu
		msg, _ := b.Send(chat, fmt.Sprintf("⌛ **Đang khởi tạo:** `%s`...", cmdStr), telebot.ModeMarkdown)
		
		// Tạo nút dừng riêng cho Message ID này
		selector := &telebot.ReplyMarkup{}
		stopBtn := selector.Data("⛔ DỪNG LỆNH NÀY", "stop_"+strconv.Itoa(msg.ID))
		selector.Inline(selector.Row(stopBtn))

		ctx, cancel := context.WithCancel(context.Background())
		pInfo := &ProcessInfo{
			Ctx:     ctx,
			Cancel:  cancel,
			Command: cmdStr,
			Lines:   make([]string, 0),
		}
		activeProcs.Store(msg.ID, pInfo)

		// Goroutine xử lý lệnh riêng biệt cho mỗi tin nhắn
		go func(targetMsg *telebot.Message, info *ProcessInfo) {
			defer cancel()
			defer activeProcs.Delete(targetMsg.ID)

			// Sử dụng stdbuf để buộc flush log liên tục
			cmd := exec.CommandContext(ctx, "sh", "-c", "stdbuf -i0 -oL -eL "+cmdStr)
			cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true} // Tạo Process Group mới

			stdout, _ := cmd.StdoutPipe()
			cmd.Stderr = cmd.Stdout // Gộp lỗi vào đầu ra chuẩn
			
			if err := cmd.Start(); err != nil {
				b.Edit(targetMsg, "❌ Lỗi thực thi: "+err.Error())
				return
			}

			info.mu.Lock()
			info.PID = cmd.Process.Pid
			info.mu.Unlock()

			// Kênh nhận log từ scanner
			logChan := make(chan string)
			go func() {
				scanner := bufio.NewScanner(stdout)
				for scanner.Scan() {
					logChan <- scanner.Text()
				}
				close(logChan)
			}()

			ticker := time.NewTicker(1500 * time.Millisecond) // Cập nhật mỗi 1.5s để tránh Telegram Rate Limit
			defer ticker.Stop()

			for {
				select {
				case <-ctx.Done():
					return // Kết thúc khi bị nhấn Stop hoặc lệnh xong
				case line, ok := <-logChan:
					if !ok {
						goto finish // Hết dữ liệu để đọc
					}
					info.mu.Lock()
					info.Lines = append(info.Lines, line)
					if len(info.Lines) > 15 { // Chỉ giữ 15 dòng cuối cùng
						info.Lines = info.Lines[1:]
					}
					info.mu.Unlock()
				case <-ticker.C:
					info.mu.Lock()
					if len(info.Lines) > 0 {
						content := strings.Join(info.Lines, "\n")
						b.Edit(targetMsg, fmt.Sprintf("🚀 **Đang chạy:** `%s`\n\n```text\n%s\n
```", cmdStr, content), telebot.ModeMarkdown, selector)
					}
					info.mu.Unlock()
				}
			}

		finish:
			cmd.Wait()
			info.mu.Lock()
			finalStatus := "✅ **Hoàn thành**"
			if ctx.Err() != nil {
				finalStatus = "🛑 **Đã dừng**"
			}
			finalLog := strings.Join(info.Lines, "\n")
			b.Edit(targetMsg, fmt.Sprintf("%s: `%s`\n\n```text\n%s\n```", finalStatus, cmdStr, finalLog), telebot.ModeMarkdown)
			info.mu.Unlock()
		}(msg, pInfo)

		return nil
	})

	fmt.Printf("Bot SSH Multi-Thread đang chạy cho ID: %d\n", adminID)
	b.Start()
}
EOF

RUN go build -o bot main.go

# Giai đoạn 2: Runtime Ubuntu 24.04 nhẹ và mạnh
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    ca-certificates coreutils curl wget git htop \
    iputils-ping dnsutils net-tools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/bot .

CMD ["./bot"]
