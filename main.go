package main

import (
	"bufio"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
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

	// Middleware kiểm tra Admin
	b.Use(func(next telebot.HandlerFunc) telebot.HandlerFunc {
		return func(c telebot.Context) error {
			if c.Sender().ID != adminID {
				return nil
			}
			return next(c)
		}
	})

	// 1. XỬ LÝ LƯU FILE (Document)
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

	// 2. XỬ LÝ NÚT DỪNG (Callback Query)
	b.Handle(telebot.OnCallback, func(c telebot.Context) error {
		data := c.Callback().Data
		if strings.HasPrefix(data, "stop_") {
			msgID, _ := strconv.Atoi(strings.TrimPrefix(data, "stop_"))
			
			procsMu.Lock()
			info, exists := activeProcs[msgID]
			procsMu.Unlock()

			if exists && info.Cmd != nil && info.Cmd.Process != nil {
				// Giết cả nhóm tiến trình (tương đương -pid trong Node)
				syscall.Kill(-info.Cmd.Process.Pid, syscall.SIGKILL)
				b.Respond(c.Callback(), &telebot.CallbackResponse{Text: "Đang dừng..."})
			} else {
				b.Respond(c.Callback(), &telebot.CallbackResponse{Text: "Lệnh không còn tồn tại."})
			}
		}
		return nil
	})

	// 3. XỬ LÝ CHẠY LỆNH (Text)
	b.Handle(telebot.OnText, func(c telebot.Context) error {
		cmdStr := c.Text()
		
		// Tạo giao diện ban đầu
		menu := &telebot.ReplyMarkup{}
		// Lưu ý: ID tin nhắn gửi đi chưa có, chúng ta sẽ cập nhật sau khi gửi
		btnStop := menu.Data("⛔ DỪNG LỆNH", "stop_pending")
		menu.Inline(menu.Row(btnStop))

		msg, _ := b.Send(fmt.Sprintf("🚀 **Exec:** `%s`", cmdStr), telebot.ModeMarkdown, menu)
		targetMsgID := msg.ID

		// Cập nhật lại Callback Data với ID chuẩn
		btnStop.Data = fmt.Sprintf("stop_%d", targetMsgID)
		b.Edit(msg, fmt.Sprintf("🚀 **Exec:** `%s`", cmdStr), telebot.ModeMarkdown, &telebot.ReplyMarkup{Inline: menu.Inline()})

		// Thiết lập lệnh chạy
		cmd := exec.Command("sh", "-c", "stdbuf -oL -eL "+cmdStr)
		cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true} // Tạo Process Group

		stdout, _ := cmd.StdoutPipe()
		stderr, _ := cmd.StderrPipe()

		info := &ProcInfo{Cmd: cmd, Logs: []string{}}
		procsMu.Lock()
		activeProcs[targetMsgID] = info
		procsMu.Unlock()

		// Đọc log đồng thời
		readLogs := func(r io.Reader) {
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

		go readLogs(stdout)
		go readLogs(stderr)

		if err := cmd.Start(); err != nil {
			return b.Edit(msg, "❌ Lỗi khởi chạy: "+err.Error())
		}

		// Ticker cập nhật tin nhắn mỗi 1.5s
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
						b.Edit(msg, fmt.Sprintf("🚀 **Running:** `%s` \n\n```text\n%s\n
```", cmdStr, output), 
							telebot.ModeMarkdown, &telebot.ReplyMarkup{Inline: menu.Inline()})
					}
					info.Mu.Unlock()
				}
			}
		}()

		// Đợi lệnh kết thúc
		err = cmd.Wait()
		done <- true

		status := "✅ Hoàn thành"
		if err != nil {
			status = "🛑 Đã dừng"
		}

		procsMu.Lock()
		delete(activeProcs, targetMsgID)
		procsMu.Unlock()

		b.Edit(msg, fmt.Sprintf("%s: `%s` \n\n`Tiến trình kết thúc.`", status, cmdStr), telebot.ModeMarkdown)
		return nil
	})

	fmt.Println("Bot Go đang chạy...")
	b.Start()
}
