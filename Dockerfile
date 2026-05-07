# Giai đoạn 1: Build nhị phân Go
FROM golang:1.22-bookworm AS builder

WORKDIR /app

# Khởi tạo và cài đặt thư viện
RUN go mod init tele-ssh-bot && \
    go get gopkg.in/telebot.v3

# Tạo mã nguồn main.go (Sử dụng 'EOF' để tránh lỗi ký tự đặc biệt)
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
	Ctx     context.Context
	Cancel  context.CancelFunc
	CmdStr  string
	Lines   []string
	PID     int
	mu      sync.Mutex
}

var (
	token      = os.Getenv("TK")
	adminID, _ = strconv.ParseInt(os.Getenv("ID"), 10, 64)
	activeProcs sync.Map // Map[int]*ProcessInfo (Key là msgID)
)

func main() {
	if token == "" || adminID == 0 {
		log.Fatal("Thiếu TK hoặc ID!")
	}

	b, err := telebot.NewBot(telebot.Settings{
		Token:  token,
		Poller: &telebot.LongPoller{Timeout: 10 * time.Second},
	})
	if err != nil {
		log.Fatal(err)
	}

	// Xử lý nút dừng riêng biệt cho từng msgID
	b.Handle(telebot.OnCallback, func(c telebot.Context) error {
		data := c.Callback().Data
		if strings.HasPrefix(data, "stop_") {
			msgID, _ := strconv.Atoi(strings.TrimPrefix(data, "stop_"))
			if val, ok := activeProcs.Load(msgID); ok {
				p := val.(*ProcessInfo)
				p.mu.Lock()
				if p.PID != 0 {
					// Tiêu diệt cả Process Group (bao gồm lệnh con)
					syscall.Kill(-p.PID, syscall.SIGKILL)
				}
				p.mu.Unlock()
				p.Cancel()
				b.Edit(c.Message(), fmt.Sprintf("🛑 **Đã dừng:** `%s`", p.CmdStr), telebot.ModeMarkdown)
				return c.Respond(&telebot.CallbackResponse{Text: "Đã dừng ngay lập tức!"})
			}
		}
		return c.Respond(&telebot.CallbackResponse{Text: "Lệnh không còn tồn tại."})
	})

	b.Handle(telebot.OnText, func(c telebot.Context) error {
		if c.Sender().ID != adminID {
			return nil
		}

		cmdStr := c.Text()
		msg, _ := b.Send(c.Chat(), fmt.Sprintf("🚀 **Exec:** `%s`...", cmdStr), telebot.ModeMarkdown)

		// Nút dừng định danh theo msg.ID
		selector := &telebot.ReplyMarkup{}
		stopBtn := selector.Data("⛔ DỪNG LỆNH NÀY", "stop_"+strconv.Itoa(msg.ID))
		selector.Inline(selector.Row(stopBtn))
		b.Edit(msg, fmt.Sprintf("🚀 **Running:** `%s`", cmdStr), telebot.ModeMarkdown, selector)

		ctx, cancel := context.WithCancel(context.Background())
		pInfo := &ProcessInfo{Ctx: ctx, Cancel: cancel, CmdStr: cmdStr}
		activeProcs.Store(msg.ID, pInfo)

		go func(target *telebot.Message, info *ProcessInfo) {
			defer cancel()
			defer activeProcs.Delete(target.ID)

			// stdbuf -oL giúp đẩy log ra ngay lập tức
			cmd := exec.CommandContext(ctx, "sh", "-c", "stdbuf -oL -eL "+info.CmdStr)
			cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
			
			stdout, _ := cmd.StdoutPipe()
			cmd.Stderr = cmd.Stdout

			if err := cmd.Start(); err != nil {
				b.Edit(target, "❌ Lỗi: "+err.Error())
				return
			}

			info.mu.Lock()
			info.PID = cmd.Process.Pid
			info.mu.Unlock()

			scanner := bufio.NewScanner(stdout)
			ticker := time.NewTicker(1500 * time.Millisecond)
			defer ticker.Stop()

			go func() {
				for scanner.Scan() {
					info.mu.Lock()
					info.Lines = append(info.Lines, scanner.Text())
					if len(info.Lines) > 10 {
						info.Lines = info.Lines[1:]
					}
					info.mu.Unlock()
				}
			}()

			for {
				select {
				case <-ctx.Done():
					goto end
				case <-ticker.C:
					info.mu.Lock()
					if len(info.Lines) > 0 {
						output := strings.Join(info.Lines, "\n")
						b.Edit(target, fmt.Sprintf("🚀 **Running:** `%s`\n\n```\n%s\n```", info.CmdStr, output), telebot.ModeMarkdown, selector)
					}
					info.mu.Unlock()
					if cmd.ProcessState != nil {
						goto end
					}
				}
			}
		end:
			cmd.Wait()
			status := "✅ Hoàn thành"
			if ctx.Err() != nil { status = "🛑 Đã dừng" }
			b.Edit(target, fmt.Sprintf("**%s:** `%s`", status, info.CmdStr), telebot.ModeMarkdown)
		}(msg, pInfo)

		return nil
	})

	log.Printf("Bot đang chạy...")
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

# Cấp quyền thực thi và chạy
RUN chmod +x bot
CMD ["./bot"]
