# Giai đoạn 1: Build
FROM golang:1.22-bookworm AS builder

WORKDIR /app

# Cài đặt thư viện cần thiết
RUN go mod init tele-ssh-bot && \
    go get gopkg.in/telebot.v3

# Sử dụng mã nguồn đã được fix lỗi cú pháp
RUN echo 'package main\n\
import (\n\
	"bufio"\n\
	"context"\n\
	"fmt"\n\
	"log"\n\
	"os"\n\
	"os/exec"\n\
	"strconv"\n\
	"strings"\n\
	"sync"\n\
	"syscall"\n\
	"time"\n\
	"gopkg.in/telebot.v3"\n\
)\n\
type ProcessInfo struct {\n\
	Ctx    context.Context\n\
	Cancel context.CancelFunc\n\
	CmdStr string\n\
	Lines  []string\n\
	PID    int\n\
	mu     sync.Mutex\n\
}\n\
var (\n\
	token      = os.Getenv("TK")\n\
	adminID, _ = strconv.ParseInt(os.Getenv("ID"), 10, 64)\n\
	procs      sync.Map\n\
)\n\
func main() {\n\
	b, _ := telebot.NewBot(telebot.Settings{\n\
		Token:  token,\n\
		Poller: &telebot.LongPoller{Timeout: 10 * time.Second},\n\
	})\n\
	b.Handle(telebot.OnCallback, func(c telebot.Context) error {\n\
		data := c.Callback().Data\n\
		if strings.HasPrefix(data, "stop_") {\n\
			id, _ := strconv.Atoi(strings.TrimPrefix(data, "stop_"))\n\
			if v, ok := procs.Load(id); ok {\n\
				p := v.(*ProcessInfo)\n\
				p.mu.Lock()\n\
				if p.PID != 0 { syscall.Kill(-p.PID, syscall.SIGKILL) }\n\
				p.mu.Unlock()\n\
				p.Cancel()\n\
				b.Edit(c.Message(), "🛑 **Đã dừng:** `" + p.CmdStr + "`", telebot.ModeMarkdown)\n\
			}\n\
		}\n\
		return c.Respond()\n\
	})\n\
	b.Handle(telebot.OnText, func(c telebot.Context) error {\n\
		if c.Sender().ID != adminID { return nil }\n\
		cmdStr := c.Text()\n\
		msg, _ := b.Send(c.Chat(), "🚀 **Running:** `" + cmdStr + "`", telebot.ModeMarkdown)\n\
		selector := &telebot.ReplyMarkup{}\n\
		stopBtn := selector.Data("⛔ DỪNG", "stop_"+strconv.Itoa(msg.ID))\n\
		selector.Inline(selector.Row(stopBtn))\n\
		b.Edit(msg, "🚀 **Running:** `" + cmdStr + "`", selector, telebot.ModeMarkdown)\n\
		ctx, cancel := context.WithCancel(context.Background())\n\
		p := &ProcessInfo{Ctx: ctx, Cancel: cancel, CmdStr: cmdStr}\n\
		procs.Store(msg.ID, p)\n\
		go func() {\n\
			defer procs.Delete(msg.ID)\n\
			cmd := exec.CommandContext(ctx, "sh", "-c", "stdbuf -oL -eL " + cmdStr)\n\
			cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}\n\
			stdout, _ := cmd.StdoutPipe()\n\
			cmd.Stderr = cmd.Stdout\n\
			if err := cmd.Start(); err != nil { return }\n\
			p.mu.Lock()\n\
			p.PID = cmd.Process.Pid\n\
			p.mu.Unlock()\n\
			scanner := bufio.NewScanner(stdout)\n\
			ticker := time.NewTicker(1500 * time.Millisecond)\n\
			defer ticker.Stop()\n\
			go func() {\n\
				for scanner.Scan() {\n\
					p.mu.Lock()\n\
					p.Lines = append(p.Lines, scanner.Text())\n\
					if len(p.Lines) > 10 { p.Lines = p.Lines[1:] }\n\
					p.mu.Unlock()\n\
				}\n\
			}()\n\
			for {\n\
				select {\n\
				case <-ctx.Done():\n\
					return\n\
				case <-ticker.C:\n\
					p.mu.Lock()\n\
					output := strings.Join(p.Lines, "\\n")\n\
					b.Edit(msg, "🚀 **Running:** `" + cmdStr + "`\\n\\n```\\n" + output + "\\n
```", selector, telebot.ModeMarkdown)\n\
					p.mu.Unlock()\n\
					if cmd.ProcessState != nil { goto end }\n\
				}\n\
			}\n\
			end: \n\
			cmd.Wait()\n\
			b.Edit(msg, "✅ **Xong:** `" + cmdStr + "`", telebot.ModeMarkdown)\n\
		}()\n\
		return nil\n\
	})\n\
	b.Start()\n\
}' > main.go

RUN go build -o bot main.go

# Giai đoạn 2: Runtime
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y ca-certificates coreutils curl wget git && apt-get clean
WORKDIR /app
COPY --from=builder /app/bot .
CMD ["./bot"]
