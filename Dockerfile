# Giai đoạn 1: Build
FROM golang:1.22-bookworm AS builder

WORKDIR /app

RUN go mod init tele-ssh-bot && \
    go get gopkg.in/telebot.v3

# Sử dụng mã nguồn đã fix lỗi chuỗi và logic
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

	// 1. XỬ LÝ LƯU FILE (Tải về thư mục /app)
	b.Handle(telebot.OnDocument, func(c telebot.Context) error {
		if c.Sender().ID != adminID { return nil }
		doc := c.Message().Document
		// Lưu trực tiếp với tên file gốc
		path := doc.FileName
		if err := b.Download(&doc.File, path); err != nil {
			return c.Reply("❌ Lỗi lưu file: " + err.Error())
		}
		return c.Reply(fmt.Sprintf("📥 Đã tải file: `%s` thành công!", path), telebot.ModeMarkdown)
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
					// Tiêu diệt toàn bộ nhóm tiến trình (Nuclear Kill)
					syscall.Kill(-p.PID, syscall.SIGKILL)
				}
				p.mu.Unlock()
				p.Cancel()
				return c.Respond(&telebot.CallbackResponse{Text: "Lệnh đang được dừng..."})
			}
		}
		return c.Respond(&telebot.CallbackResponse{Text: "Lệnh không còn hoạt động."})
	})

	// 3. XỬ LÝ LỆNH ĐA LUỒNG
	b.Handle(telebot.OnText, func(c telebot.Context) error {
		if c.Sender().ID != adminID { return nil }
		cmdStr := c.Text()
		
		msg, _ := b.Send(c.Chat(), "🚀 **Đang khởi tạo...**")

		selector := &telebot.ReplyMarkup{}
		btn := selector.Data("⛔ DỪNG LỆNH NÀY", "stop_"+strconv.Itoa(msg.ID))
		selector.Inline(selector.Row(btn))
		
		b.Edit(msg, fmt.Sprintf("🚀 **Exec:** `%s`", cmdStr), selector, telebot.ModeMarkdown)

		ctx, cancel := context.WithCancel(context.Background())
		p := &ProcessInfo{Ctx: ctx, Cancel: cancel, CmdStr: cmdStr}
		procs.Store(msg.ID, p)

		go func() {
			defer procs.Delete(msg.ID)
			defer cancel()

			// Sử dụng stdbuf để đẩy log real-time
			cmd := exec.CommandContext(ctx, "sh", "-c", "stdbuf -oL -eL "+cmdStr)
			cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
			
			stdout, _ := cmd.StdoutPipe()
			cmd.Stderr = cmd.Stdout
			if err := cmd.Start(); err != nil {
				b.Edit(msg, "❌ Lỗi thực thi: "+err.Error())
				return
			}

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
					if len(p.Lines) > 12 { p.Lines = p.Lines[1:] }
					p.mu.Unlock()
				}
			}()

			for {
				select {
				case <-ctx.Done():
					goto end
				case <-ticker.C:
					p.mu.Lock()
					if len(p.Lines) > 0 {
						output := strings.Join(p.Lines, "\n")
						// Dùng nháy ngược để tránh lỗi newline in string
						b.Edit(msg, fmt.Sprintf("🚀 **Running:** `%s` \n\n```text\n%s\n
```", cmdStr, output), selector, telebot.ModeMarkdown)
					}
					p.mu.Unlock()
					if cmd.ProcessState != nil { goto end }
				}
			}
			end:
			cmd.Wait()
			status := "✅ Hoàn thành"
			if ctx.Err() != nil { status = "🛑 Đã dừng" }
			b.Edit(msg, fmt.Sprintf("%s: `%s`\n\n`Tiến trình đã kết thúc.`", status, cmdStr), telebot.ModeMarkdown)
		}()
		return nil
	})

	log.Println("Bot SSH Ultra is running...")
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
