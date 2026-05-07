# Giai đoạn 1: Build nhị phân Go
FROM golang:1.22-bookworm AS builder

WORKDIR /app

RUN go mod init tele-ssh-bot && \
    go get gopkg.in/telebot.v3

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
	activeProcs sync.Map 
)

func main() {
	if token == "" || adminID == 0 {
		log.Fatal("Thiếu TK hoặc ID trên môi trường!")
	}

	b, err := telebot.NewBot(telebot.Settings{
		Token:  token,
		Poller: &telebot.LongPoller{Timeout: 10 * time.Second},
	})
	if err != nil {
		log.Fatal(err)
	}

	// 1. XỬ LÝ NÚT DỪNG
	b.Handle(telebot.OnCallback, func(c telebot.Context) error {
		data := c.Callback().Data
		if strings.HasPrefix(data, "stop_") {
			msgID, _ := strconv.Atoi(strings.TrimPrefix(data, "stop_"))
			if val, ok := activeProcs.Load(msgID); ok {
				p := val.(*ProcessInfo)
				p.mu.Lock()
				if p.PID != 0 {
					syscall.Kill(-p.PID, syscall.SIGKILL) // Kill toàn bộ group con
				}
				p.mu.Unlock()
				p.Cancel()
				return c.Respond(&telebot.CallbackResponse{Text: "Đang dừng lệnh..."})
			}
		}
		return c.Respond(&telebot.CallbackResponse{Text: "Lệnh đã xong hoặc không tồn tại."})
	})

	// 2. XỬ LÝ LƯU FILE (Download về thư mục hiện tại)
	b.Handle(telebot.OnDocument, func(c telebot.Context) error {
		if c.Sender().ID != adminID { return nil }
		doc := c.Message().Document
		if err := b.Download(&doc.File, doc.FileName); err != nil {
			return c.Reply("❌ Lỗi lưu file: " + err.Error())
		}
		return c.Reply(fmt.Sprintf("📥 Đã lưu file: `%s`", doc.FileName), telebot.ModeMarkdown)
	})

	// 3. XỬ LÝ CHẠY LỆNH ĐA LUỒNG
	b.Handle(telebot.OnText, func(c telebot.Context) error {
		if c.Sender().ID != adminID { return nil }
		cmdStr := c.Text()
		
		msg, _ := b.Send(c.Chat(), fmt.Sprintf("🚀 **Exec:** `%s`", cmdStr), telebot.ModeMarkdown)

		selector := &telebot.ReplyMarkup{}
		stopBtn := selector.Data("⛔ DỪNG LỆNH", "stop_"+strconv.Itoa(msg.ID))
		selector.Inline(selector.Row(stopBtn))
		
		b.Edit(msg, fmt.Sprintf("🚀 **Running:** `%s`", cmdStr), selector, telebot.ModeMarkdown)

		ctx, cancel := context.WithCancel(context.Background())
		pInfo := &ProcessInfo{Ctx: ctx, Cancel: cancel, CmdStr: cmdStr}
		activeProcs.Store(msg.ID, pInfo)

		go func(target *telebot.Message, info *ProcessInfo) {
			defer activeProcs.Delete(target.ID)
			defer cancel()

			cmd := exec.CommandContext(ctx, "sh", "-c", "stdbuf -oL -eL "+info.CmdStr)
			cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
			
			stdout, _ := cmd.StdoutPipe()
			cmd.Stderr = cmd.Stdout

			if err := cmd.Start(); err != nil {
				b.Edit(target, "❌ Lỗi khởi chạy: "+err.Error())
				return
			}

			info.mu.Lock()
			info.PID = cmd.Process.Pid
			info.mu.Unlock()

			scanner := bufio.NewScanner(stdout)
			ticker := time.NewTicker(1500 * time.Millisecond)
			defer ticker.Stop()

			// Goroutine đọc log
			go func() {
				for scanner.Scan() {
					info.mu.Lock()
					info.Lines = append(info.Lines, scanner.Text())
					if len(info.Lines) > 10 { info.Lines = info.Lines[1:] }
					info.mu.Unlock()
				}
			}()

			for {
				select {
				case <-ctx.Done(): // Khi nhấn nút dừng
					goto end
				case <-ticker.C:
					info.mu.Lock()
					if len(info.Lines) > 0 {
						output := strings.Join(info.Lines, "\n")
						b.Edit(target, fmt.Sprintf("🚀 **Running:** `%s`\n\n```\n%s\n
```", info.CmdStr, output), selector, telebot.ModeMarkdown)
					}
					info.mu.Unlock()
					if cmd.ProcessState != nil { goto end }
				}
			}
		end:
			cmd.Wait()
			finalStatus := "✅ Hoàn thành"
			if ctx.Err() != nil { finalStatus = "🛑 Đã dừng" }
			
			// Khi kết thúc, cập nhật tin nhắn cuối cùng (Xóa nút bấm)
			b.Edit(target, fmt.Sprintf("%s: `%s`\n\n`Tiến trình kết thúc.`", finalStatus, info.CmdStr), telebot.ModeMarkdown)
		}(msg, pInfo)

		return nil
	})

	log.Println("Bot is running...")
	b.Start()
}
EOF

RUN go build -o bot main.go

# Giai đoạn 2: Runtime
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y ca-certificates coreutils curl wget git htop iputils-ping dnsutils net-tools && apt-get clean
WORKDIR /app
COPY --from=builder /app/bot .
RUN chmod +x bot
CMD ["./bot"]
