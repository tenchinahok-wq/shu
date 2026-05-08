package main

import (
	"bufio"
	"context"
	"fmt"
	"html"
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

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api/v5"
)

type ProcInfo struct {
	Cmd    *exec.Cmd
	Logs   []string
	Mu     sync.Mutex
	Cancel context.CancelFunc
}

var (
	activeProcs = make(map[int]*ProcInfo)
	procsMu     sync.Mutex
	adminID     int64
)

func main() {
	token := os.Getenv("TK")
	idStr := os.Getenv("ID")
	adminID, _ = strconv.ParseInt(idStr, 10, 64)

	bot, err := tgbotapi.NewBotAPI(token)
	if err != nil {
		log.Panic(err)
	}

	log.Printf("Bot Go đang chạy trên account %s", bot.Self.UserName)

	u := tgbotapi.NewUpdate(0)
	u.Timeout = 60
	updates := bot.GetUpdatesChan(u)

	for update := range updates {
		if update.Message != nil {
			if update.Message.From.ID != adminID {
				continue
			}

			if update.Message.Document != nil {
				go handleDocument(bot, update.Message)
			} else if update.Message.Text != "" {
				go handleCommand(bot, update.Message)
			}
		} else if update.CallbackQuery != nil {
			go handleCallback(bot, update.CallbackQuery)
		}
	}
}

func handleDocument(bot *tgbotapi.BotAPI, msg *tgbotapi.Message) {
	fileID := msg.Document.FileID
	fileName := msg.Document.FileName
	fileURL, _ := bot.GetFileDirectURL(fileID)

	resp, err := http.Get(fileURL)
	if err != nil {
		reply(bot, msg.Chat.ID, "❌ Lỗi tải file: "+err.Error())
		return
	}
	defer resp.Body.Close()

	out, err := os.Create(fileName)
	if err != nil {
		reply(bot, msg.Chat.ID, "❌ Lỗi lưu file: "+err.Error())
		return
	}
	defer out.Close()

	io.Copy(out, resp.Body)
	reply(bot, msg.Chat.ID, fmt.Sprintf("✅ Đã lưu file: <code>%s</code>", html.EscapeString(fileName)))
}

func handleCommand(bot *tgbotapi.BotAPI, msg *tgbotapi.Message) {
	cmdStr := msg.Text
	// Tạo message gốc với nút Cancel
	sentMsg, _ := bot.Send(tgbotapi.MessageConfig{
		BaseChat: tgbotapi.BaseChat{
			ChatID:      msg.Chat.ID,
			ReplyMarkup: stopButton(msg.MessageID + 1), // Dự đoán ID tiếp theo hoặc dùng ID message này
		},
		Text:      fmt.Sprintf("<b>Lệnh:</b> <code>%s</code>", html.EscapeString(cmdStr)),
		ParseMode: "HTML",
	})

	targetMsgID := sentMsg.MessageID
	ctx, cancel := context.WithCancel(context.Background())
	
	cmd := exec.CommandContext(ctx, "sh", "-c", cmdStr)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true} // Tạo process group để kill sạch

	stdout, _ := cmd.StdoutPipe()
	stderr, _ := cmd.StderrPipe()

	pInfo := &ProcInfo{Cmd: cmd, Logs: []string{}, Cancel: cancel}
	procsMu.Lock()
	activeProcs[targetMsgID] = pInfo
	procsMu.Unlock()

	// Đọc log
	var wg sync.WaitGroup
	wg.Add(2)
	readLogs := func(r io.Reader, limit int) {
		defer wg.Done()
		scanner := bufio.NewScanner(r)
		for scanner.Scan() {
			pInfo.Mu.Lock()
			pInfo.Logs = append(pInfo.Logs, scanner.Text())
			if len(pInfo.Logs) > limit {
				pInfo.Logs = pInfo.Logs[1:]
			}
			pInfo.Mu.Unlock()
		}
	}
	go readLogs(stdout, 15)
	go readLogs(stderr, 5)

	cmd.Start()

	// Ticker update message mỗi 3s
	ticker := time.NewTicker(3 * time.Second)
	done := make(chan bool)

	go func() {
		for {
			select {
			case <-ticker.C:
				pInfo.Mu.Lock()
				if len(pInfo.Logs) > 0 {
					output := strings.Join(pInfo.Logs, "\n")
					editMsg(bot, msg.Chat.ID, targetMsgID, 
						fmt.Sprintf("<b>Lệnh:</b> <code>%s</code>\n\n<pre>%s</pre>", 
						html.EscapeString(cmdStr), html.EscapeString(output)), 
						true)
				}
				pInfo.Mu.Unlock()
			case <-done:
				return
			}
		}
	}()

	err := cmd.Wait()
	ticker.Stop()
	done <- true

	status := "✅ Success"
	if err != nil {
		status = "❌ Cancel/Error"
	}

	// Cập nhật lần cuối: Giữ nguyên lệnh ở đầu, thêm thông báo kết thúc
	finalLog := ""
	pInfo.Mu.Lock()
	if len(pInfo.Logs) > 0 {
		finalLog = "\n\n<pre>" + html.EscapeString(strings.Join(pInfo.Logs, "\n")) + "</pre>"
	}
	pInfo.Mu.Unlock()

	editMsg(bot, msg.Chat.ID, targetMsgID, 
		fmt.Sprintf("%s: <code>%s</code>%s\n\n<b>The process is over.</b>", 
		status, html.EscapeString(cmdStr), finalLog), 
		false)

	procsMu.Lock()
	delete(activeProcs, targetMsgID)
	procsMu.Unlock()
}

func handleCallback(bot *tgbotapi.BotAPI, query *tgbotapi.CallbackQuery) {
	if strings.HasPrefix(query.Data, "stop_") {
		msgID, _ := strconv.Atoi(strings.TrimPrefix(query.Data, "stop_"))
		procsMu.Lock()
		pInfo, ok := activeProcs[msgID]
		procsMu.Unlock()

		if ok && pInfo.Cmd != nil && pInfo.Cmd.Process != nil {
			// Kill toàn bộ process group
			syscall.Kill(-pInfo.Cmd.Process.Pid, syscall.SIGKILL)
			pInfo.Cancel()
			bot.Request(tgbotapi.NewCallback(query.ID, "Đang dừng lệnh..."))
		} else {
			bot.Request(tgbotapi.NewCallback(query.ID, "Lệnh không còn tồn tại."))
		}
	}
}

func stopButton(msgID int) tgbotapi.InlineKeyboardMarkup {
	return tgbotapi.NewInlineKeyboardMarkup(
		tgbotapi.NewInlineKeyboardRow(
			tgbotapi.NewInlineKeyboardButtonData("Cancel", fmt.Sprintf("stop_%d", msgID)),
		),
	)
}

func reply(bot *tgbotapi.BotAPI, chatID int64, text string) {
	msg := tgbotapi.NewMessage(chatID, text)
	msg.ParseMode = "HTML"
	bot.Send(msg)
}

func editMsg(bot *tgbotapi.BotAPI, chatID int64, msgID int, text string, withButton bool) {
	edit := tgbotapi.NewEditMessageText(chatID, msgID, text)
	edit.ParseMode = "HTML"
	if withButton {
		markup := stopButton(msgID)
		edit.ReplyMarkup = &markup
	}
	bot.Send(edit)
}ẻ
