# Giai đoạn 1: Build
FROM golang:1.22-bookworm AS builder

WORKDIR /app

RUN go mod init tele-ssh-bot && \
    go get gopkg.in/telebot.v3

# Sử dụng HEREDOC để ghi file Go an toàn nhất
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
	Ctx    context.Context
	Cancel context.CancelFunc
	CmdStr string
	Lines  []string
	PID    int
	mu     sync.Mutex
}

var (
	token      = os.Getenv("TK")
	adminID, _ = strconv.ParseInt(os.Getenv("ID"), 10, 64)
	procs      sync.Map
)

func main() {
	if token == "" || adminID == 0 {
		log.Fatal("LỖI: Thiếu biến TK hoặc ID!")
	}

	b, _ := telebot.NewBot(telebot.Settings{
		Token:  token,
		Poller: &telebot.LongPoller{Timeout: 10 * time.Second},
	})

	// 1. XỬ LÝ LƯU FILE
	b.Handle(telebot.OnDocument, func(c telebot.Context) error {
		if c.Sender().ID != adminID { return nil }
		f := c.Message().Document
		path := "./" + f.FileName
		if err := b.Download(&f.File, path); err != nil {
			return c.Reply("❌ Lỗi tải file: " + err.Error())
		}
		return c.Reply("📥 Đã lưu file: `" + f.FileName + "`", telebot.ModeMarkdown)
	})

	// 2. XỬ LÝ NÚT DỪNG
	b.Handle(telebot.OnCallback, func(c telebot.Context) error {
		data := c.Callback().Data
		if strings.HasPrefix(data, "stop_") {
			id, _ := strconv.Atoi(strings.TrimPrefix(data, "stop_"))
			if v, ok := procs.Load(id); ok {
				p := v.(*ProcessInfo)
				p.mu.Lock()
				if p.PID != 0 {
					syscall.Kill(-p.PID, syscall.SIGKILL)
				}
				p.mu.Unlock()
				p.Cancel()
				return c.Respond(&telebot.CallbackResponse{Text: "Đã ép dừng!"})
			}
		}
		return c.Respond(&telebot.CallbackResponse{Text: "Lệnh đã kết thúc."})
	})

	// 3. XỬ LÝ CHẠY LỆNH
	b.Handle(telebot.OnText, func(c telebot.Context) error {
		if c.Sender().ID != adminID { return nil }
		cmdStr := c.Text()
		
		msg, _ := b.Send(c.Chat(), "🚀 **Đang chạy:** `" + cmdStr + "`", telebot.ModeMarkdown)

		selector := &telebot.ReplyMarkup{}
		btn := selector.Data("⛔ DỪNG LỆNH", "stop_"+strconv.Itoa(msg.ID))
		selector.Inline(selector.Row(btn))
		b.Edit(msg, "🚀 **Đang chạy:** `" + cmdStr + "`", selector, telebot.ModeMarkdown)

		ctx, cancel := context.WithCancel(context.Background())
		p := &ProcessInfo{Ctx: ctx, Cancel: cancel, CmdStr: cmdStr}
		procs.Store(msg.ID, p)

		go func() {
			defer procs.Delete(msg.ID)
			defer cancel()

			cmd := exec.CommandContext(ctx, "sh", "-c", "stdbuf -oL -eL " + cmdStr)
			cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
			
			stdout, _ := cmd.StdoutPipe()
			cmd.Stderr = cmd.Stdout
			cmd.Start()

			p.mu.Lock()
			p.PID = cmd.Process.Pid
			p.mu.Unlock()

			scanner := bufio.NewScanner(stdout)
			ticker := time.NewTicker(1500 * time.Millisecond)
			defer ticker.Stop()

			go func() {
				for scanner.Scan() {
					p.mu.Lock()
					p.Lines = append(p.Lines, scanner.Text())
					if len(p.Lines) > 10 { p.Lines = p.Lines[1:] }
					p.mu.Unlock()
				}
			}()

			for {
				select {
				case <-ctx.Done():
					goto final
				case <-ticker.C:
					p.mu.Lock()
					output := strings.Join(p.Lines, "\n")
					if output != "" {
						b.Edit(msg, "🚀 **Running:** `" + cmdStr + "`\n\n```\n" + output + "\n
```", selector, telebot.ModeMarkdown)
					}
					p.mu.Unlock()
					if cmd.ProcessState != nil { goto final }
				}
			}
			final:
			cmd.Wait()
			status := "✅ Xong"
			if ctx.Err() != nil { status = "🛑 Đã dừng" }
			b.Edit(msg, status + ": `" + cmdStr + "`", telebot.ModeMarkdown)
		}()
		return nil
	})

	log.Println("Bot running...")
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
