# Giai đoạn 1: Build nhị phân Go
FROM golang:1.22-bookworm AS builder

WORKDIR /app

RUN go mod init tele-ssh-bot && \
    go get gopkg.in/telebot.v3

# Sử dụng mã nguồn đã được bao bọc cực kỳ cẩn thận
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

	// 1. XỬ LÝ LƯU FILE (Tải về thư mục hiện tại)
	b.Handle(telebot.OnDocument, func(c telebot.Context) error {
		if c.Sender().ID != adminID { return nil }
		doc := c.Message().Document
		path := doc.FileName
		if err := b.Download(&doc.File, path); err != nil {
			return c.Reply("❌ Lỗi lưu file: " + err.Error())
		}
		return c.Reply("📥 Đã lưu file: `" + path + "`", telebot.ModeMarkdown)
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
				return c.Respond(&telebot.CallbackResponse{Text: "Đang tiêu diệt tiến trình..."})
			}
		}
		return c.Respond(&telebot.CallbackResponse{Text: "Lệnh không còn tồn tại."})
	})

	// 3. XỬ LÝ CHẠY LỆNH (ĐA LUỒNG)
	b.Handle(telebot.OnText, func(c telebot.Context) error {
		if c.Sender().ID != adminID { return nil }
		cmdStr := c.Text()
		
		msg, _ := b.Send(c.Chat(), "⌛ Đang chuẩn bị lệnh...")

		selector := &telebot.ReplyMarkup{}
		btn := selector.Data("⛔ DỪNG LỆNH NÀY", "stop_"+strconv.Itoa(msg.ID))
		selector.Inline(selector.Row(btn))
		
		b.Edit(msg, "🚀 **Exec:** `" + cmdStr + "`", selector, telebot.ModeMarkdown)

		ctx, cancel := context.WithCancel(context.Background())
		p := &ProcessInfo{Ctx: ctx, Cancel: cancel, CmdStr: cmdStr}
		procs.Store(msg.ID, p)

		go func(target *telebot.Message, info *ProcessInfo) {
			defer procs.Delete(target.ID)
			defer cancel()

			cmd := exec.CommandContext(ctx, "sh", "-c", "stdbuf -oL -eL " + info.CmdStr)
			cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
			
			stdout, _ := cmd.StdoutPipe()
			cmd.Stderr = cmd.Stdout
			if err := cmd.Start(); err != nil {
				b.Edit(target, "❌ Lỗi: " + err.Error())
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
					if len(info.Lines) > 12 { info.Lines = info.Lines[1:] }
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
						// Dùng nháy ngược để an toàn tuyệt đối cho chuỗi nhiều dòng
						b.Edit(target, "🚀 **Running:** `" + info.CmdStr + "`\n\n```text\n" + output + "\n
```", selector, telebot.ModeMarkdown)
					}
					info.mu.Unlock()
					if cmd.ProcessState != nil { goto end }
				}
			}
			end:
			cmd.Wait()
			status := "✅ Hoàn thành"
			if ctx.Err() != nil { status = "🛑 Đã dừng" }
			b.Edit(target, status + ": `" + info.CmdStr + "`\n\n`Tiến trình kết thúc.`", telebot.ModeMarkdown)
		}(msg, p)

		return nil
	})

	log.Println("Bot is running...")
	b.Start()
}
EOF

RUN go build -o bot main.go

# Giai đoạn 2: Runtime Ubuntu 24.04
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y ca-certificates coreutils curl wget git htop iputils-ping dnsutils net-tools && apt-get clean
WORKDIR /app
COPY --from=builder /app/bot .
RUN chmod +x bot
CMD ["./bot"]
