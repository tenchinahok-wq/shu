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

	// Middleware Admin
	b.Use(func(next telebot.HandlerFunc) telebot.HandlerFunc {
		return func(c telebot.Context) error {
			if c.Sender().ID != adminID {
				return nil
			}
			return next(c)
		}
	})

	// 1. LƯU FILE
	b.Handle(telebot.OnDocument, func(c telebot.Context) error {
		doc := c.Message().Document
		fileReader, err := b.File(&doc.File)
		if err != nil {
			return c.Reply("❌ Lỗi lấy file: " + err.Error())
		}
		defer fileReader.Close()

		out, err := os.Create(doc.FileName)
		if err != nil {
			return c.Reply("❌ Lỗi tạo file: " + err.Error())
		}
		defer out.Close()

		io.Copy(out, fileReader)
		return c.Send(fmt.Sprintf("📥 Đã lưu file: `%s`", doc.FileName), telebot.ModeMarkdown)
	})

	// 2. NÚT DỪNG
	b.Handle(telebot.OnCallback, func(c telebot.Context) error {
		data := c.Callback().Data
		if strings.HasPrefix(data, "stop_") {
			msgID, _ := strconv.Atoi(strings.TrimPrefix(data, "stop_"))
			procsMu.Lock()
			info, exists := activeProcs[msgID]
			procsMu.Unlock()

			if exists && info.Cmd != nil && info.Cmd.Process != nil {
				// Kill cả process group
				_ = syscall.Kill(-info.Cmd.Process.Pid, syscall.SIGKILL)
				b.Respond(c.Callback(), &telebot.CallbackResponse{Text: "Đang dừng..."})
			} else {
				b.Respond(c.Callback(), &telebot.CallbackResponse{Text: "Lệnh không còn tồn tại."})
			}
		}
		return nil
	})

	// 3. CHẠY LỆNH
	b.Handle(telebot.OnText, func(c telebot.Context) error {
		cmdStr := c.Text()
		menu := &telebot.ReplyMarkup{}
		// Bước 1: Gửi tin nhắn khởi tạo
		msg, _ := b.Send(fmt.Sprintf("🚀 **Exec:** `%s`", cmdStr), telebot.ModeMarkdown)
		
		// Bước 2: Tạo nút dừng với ID thật của tin nhắn vừa gửi
		btnStop := menu.Data("⛔ DỪNG LỆNH", "stop_"+strconv.Itoa(msg.ID))
		menu.Inline(menu.Row(btnStop))
		b.Edit(msg, fmt.Sprintf("🚀 **Exec:** `%s`", cmdStr), telebot.ModeMarkdown, menu)

		cmd := exec.Command("sh", "-c", "stdbuf -oL -eL "+cmdStr)
		cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

		stdout, _ := cmd.StdoutPipe()
		stderr, _ := cmd.StderrPipe()

		info := &ProcInfo{Cmd: cmd, Logs: []string{}}
		procsMu.Lock()
		activeProcs[msg.ID] = info
		procsMu.Unlock()

		// Luồng đọc log
		readFn := func(r io.Reader) {
			scanner := bufio.NewScanner(r)
			for scanner.Scan() {
				info.Mu.Lock()
				info.Logs = append(info.Logs, scanner.Text())
				if len(info.Logs) > 12 {
					info.Logs = info.Logs[1:]
				}
				info.Mu.Unlock()
			}
		}
		go readFn(stdout)
		go readFn(stderr)

		if err := cmd.Start(); err != nil {
			return b.Edit(msg, "❌ Lỗi: "+err.Error())
		}

		// Luồng cập nhật UI (Ticker)
		done := make(chan bool)
		go func() {
			ticker := time.NewTicker(1500 * time.Millisecond)
			defer ticker.Stop()
			for {
				select {
				case <-done:
					return
				case <-ticker.C:
					info.Mu.Lock()
					if len(info.Logs) > 0 {
						output := strings.Join(info.Logs, "\n")
						txt := fmt.Sprintf("🚀 **Running:** `%s` \n\n```text\n%s\n
```", cmdStr, output)
						b.Edit(msg, txt, telebot.ModeMarkdown, menu)
					}
					info.Mu.Unlock()
				}
			}
		}()

		err := cmd.Wait()
		done <- true

		status := "✅ Hoàn thành"
		if err != nil {
			status = "🛑 Đã dừng"
		}

		procsMu.Lock()
		delete(activeProcs, msg.ID)
		procsMu.Unlock()

		b.Edit(msg, fmt.Sprintf("%s: `%s` \n\n`Tiến trình kết thúc.`", status, cmdStr), telebot.ModeMarkdown)
		return nil
	})

	log.Println("Bot Go đang chạy...")
	b.Start()
}
