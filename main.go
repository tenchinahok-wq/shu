package main

import (
	"bufio"
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

type ProcInfo struct {
	Cmd  *exec.Cmd
	Logs []string
	Mu   sync.Mutex
}

var (
	activeProcs = make(map[int]*ProcInfo)
	procsMu     sync.Mutex
	adminID, _  = strconv.ParseInt(os.Getenv("ID"), 10, 64)
	botToken    = os.Getenv("TK")
)

func main() {
	pref := telebot.Settings{
		Token:  botToken,
		Poller: &telebot.LongPoller{Timeout: 10 * time.Second},
	}

	b, err := telebot.NewBot(pref)
	if err != nil {
		log.Fatal(err)
	}

	b.Use(func(next telebot.HandlerFunc) telebot.HandlerFunc {
		return func(c telebot.Context) error {
			if c.Sender().ID != adminID {
				return nil
			}
			return next(c)
		}
	})

	b.Handle(telebot.OnDocument, func(c telebot.Context) error {
		doc := c.Message().Document
		f, err := b.File(&doc.File)
		if err != nil {
			return c.Reply("Error: " + err.Error())
		}
		defer f.Close()
		out, _ := os.Create(doc.FileName)
		defer out.Close()
		io.Copy(out, f)
		msg := fmt.Sprintf("📥 Saved: `%s`", doc.FileName)
		return c.Send(msg, telebot.ModeMarkdown)
	})

	b.Handle(telebot.OnCallback, func(c telebot.Context) error {
		data := c.Callback().Data
		if strings.HasPrefix(data, "stop_") {
			idStr := strings.TrimPrefix(data, "stop_")
			msgID, _ := strconv.Atoi(idStr)
			procsMu.Lock()
			info, exists := activeProcs[msgID]
			procsMu.Unlock()
			if exists && info.Cmd != nil && info.Cmd.Process != nil {
				_ = syscall.Kill(-info.Cmd.Process.Pid, syscall.SIGKILL)
				b.Respond(c.Callback(), &telebot.CallbackResponse{Text: "Stopping..."})
			}
		}
		return nil
	})

	b.Handle(telebot.OnText, func(c telebot.Context) error {
		cmdStr := c.Text()
		header := fmt.Sprintf("🚀 **Exec:** `%s`", cmdStr)
		msg, err := b.Send(c.Recipient(), header, telebot.ModeMarkdown)
		if err != nil {
			return err
		}

		menu := &telebot.ReplyMarkup{}
		btn := menu.Data("⛔ DỪNG LỆNH", "stop_"+strconv.Itoa(msg.ID))
		menu.Inline(menu.Row(btn))
		b.Edit(msg, header, telebot.ModeMarkdown, menu)

		cmd := exec.Command("sh", "-c", "stdbuf -oL -eL "+cmdStr)
		cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
		stdout, _ := cmd.StdoutPipe()
		stderr, _ := cmd.StderrPipe()

		info := &ProcInfo{Cmd: cmd, Logs: []string{}}
		procsMu.Lock()
		activeProcs[msg.ID] = info
		procsMu.Unlock()

		reader := func(r io.Reader) {
			s := bufio.NewScanner(r)
			for s.Scan() {
				info.Mu.Lock()
				info.Logs = append(info.Logs, s.Text())
				if len(info.Logs) > 12 {
					info.Logs = info.Logs[1:]
				}
				info.Mu.Unlock()
			}
		}
		go reader(stdout)
		go reader(stderr)

		if err := cmd.Start(); err != nil {
			b.Edit(msg, "❌ Error: "+err.Error())
			return nil
		}

		done := make(chan bool)
		go func() {
			t := time.NewTicker(1500 * time.Millisecond)
			defer t.Stop()
			for {
				select {
				case <-done:
					return
				case <-t.C:
					info.Mu.Lock()
					if len(info.Logs) > 0 {
						logs := strings.Join(info.Logs, "\n")
						txt := fmt.Sprintf("🚀 **Running:** `%s` \n\n```text\n%s\n```", cmdStr, logs)
						b.Edit(msg, txt, telebot.ModeMarkdown, menu)
					}
					info.Mu.Unlock()
				}
			}
		}()

		waitErr := cmd.Wait()
		done <- true

		status := "✅ Hoàn thành"
		if waitErr != nil {
			status = "🛑 Đã dừng"
		}

		procsMu.Lock()
		delete(activeProcs, msg.ID)
		procsMu.Unlock()

		finalTxt := fmt.Sprintf("%s: `%s` \n\n`Tiến trình kết thúc.`", status, cmdStr)
		b.Edit(msg, finalTxt, telebot.ModeMarkdown)
		return nil
	})

	log.Println("Bot Go is running...")
	b.Start()
}
