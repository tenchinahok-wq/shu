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
	// Gửi tin nhắn khởi tạo
	sentMsg, _ := bot.Send(tgbotapi.MessageConfig{
		BaseChat: tgbotapi.BaseChat{
			ChatID:      msg.Chat.ID,
			ReplyMarkup: stopButton(msg.MessageID + 1), 
		},
		Text:      fmt.Sprintf("<b>🚀 Đang chạy:</b> <code>%s</code>", html.EscapeString(cmdStr)),
		ParseMode: "HTML",
	})

	targetMsgID := sentMsg.MessageID
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	cmd := exec.CommandContext(ctx, "sh", "-c", cmdStr)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true} 

	stdout, _ := cmd.StdoutPipe()
	stderr, _ := cmd.StderrPipe()

	pInfo := &ProcInfo{Cmd: cmd, Logs: []string{}, Cancel: cancel}
	procsMu.Lock()
	activeProcs[targetMsgID] = pInfo
	procsMu.Unlock()

	var (
		lastUpdate = time.Now()
		updateMu   sync.Mutex
	)

	// Hàm cập nhật message (có giới hạn tốc độ để tránh spam API)
	updateUI := func(final bool) {
		updateMu.Lock()
		defer updateMu.Unlock()

		// Chỉ cập nhật nếu cách lần cuối 1.2s hoặc là lần cuối cùng
		if final || time.Since(lastUpdate) > 1200*time.Millisecond {
			pInfo.Mu.Lock()
			logContent := strings.Join(pInfo.Logs, "\n")
			pInfo.Mu.Unlock()

			if logContent == "" && !final {
				return
			}

			statusHeader := "🚀 Đang chạy"
			if final {
				statusHeader = "✅ Kết thúc"
			}

			text := fmt.Sprintf("<b>%s:</b> <code>%s</code>\n\n<pre>%s</pre>", 
				statusHeader, html.EscapeString(cmdStr), html.EscapeString(logContent))
			
			if final {
				text += "\n<b>The process is over.</b>"
			}

			edit := tgbotapi.NewEditMessageText(msg.Chat.ID, targetMsgID, text)
			edit.ParseMode = "HTML"
			if !final {
				markup := stopButton(targetMsgID)
				edit.ReplyMarkup = &markup
			}
			bot.Send(edit)
			lastUpdate = time.Now()
		}
	}

	// Đọc log
	readFunc := func(r io.Reader, limit int) {
		scanner := bufio.NewScanner(r)
		for scanner.Scan() {
			pInfo.Mu.Lock()
			pInfo.Logs = append(pInfo.Logs, scanner.Text())
			if len(pInfo.Logs) > limit {
				pInfo.Logs = pInfo.Logs[1:]
			}
			pInfo.Mu.Unlock()
			updateUI(false)
		}
	}

	go readFunc(stdout, 15)
	go readFunc(stderr, 5)

	err := cmd.Start()
	if err != nil {
		editMsg(bot, msg.Chat.ID, targetMsgID, "❌ Lỗi: "+err.Error(), false)
		return
	}

	cmd.Wait()
	updateUI(true) // Cập nhật lần cuối cùng

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
			syscall.Kill(-pInfo.Cmd.Process.Pid, syscall.SIGKILL)
			pInfo.Cancel()
			bot.Request(tgbotapi.NewCallback(query.ID, "Đang dừng..."))
		} else {
			bot.Request(tgbotapi.NewCallback(query.ID, "Tiến trình đã kết thúc."))
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
}
