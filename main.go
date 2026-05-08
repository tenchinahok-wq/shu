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

	log.Printf("Bot Go đang chạy...")

	u := tgbotapi.NewUpdate(0)
	u.Timeout = 60
	updates := bot.GetUpdatesChan(u)

	for update := range updates {
		if update.Message != nil && update.Message.From.ID == adminID {
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

func handleCommand(bot *tgbotapi.BotAPI, msg *tgbotapi.Message) {
	cmdStr := msg.Text
	// Gửi tin nhắn ban đầu (giống Node: ctx.reply)
	sentMsg, _ := bot.Send(tgbotapi.MessageConfig{
		BaseChat: tgbotapi.BaseChat{
			ChatID:      msg.Chat.ID,
			ReplyMarkup: stopButton(msg.MessageID + 1),
		},
		Text:      fmt.Sprintf("<code>%s</code>", html.EscapeString(cmdStr)),
		ParseMode: "HTML",
	})

	targetMsgID := sentMsg.MessageID
	ctx, cancel := context.WithCancel(context.Background())
	
	// QUAN TRỌNG: Dùng stdbuf -oL -eL để ép hệ thống xuất log ngay lập tức (Line Buffering)
	cmd := exec.CommandContext(ctx, "sh", "-c", "stdbuf -oL -eL "+cmdStr)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	stdout, _ := cmd.StdoutPipe()
	stderr, _ := cmd.StderrPipe()

	pInfo := &ProcInfo{Cmd: cmd, Logs: []string{}, Cancel: cancel}
	procsMu.Lock()
	activeProcs[targetMsgID] = pInfo
	procsMu.Unlock()

	// Luồng đọc log (giống child.stdout.on('data'))
	readLogs := func(r io.Reader, limit int) {
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
	go readLogs(stdout, 12)
	go readLogs(stderr, 3)

	if err := cmd.Start(); err != nil {
		editMsg(bot, msg.Chat.ID, targetMsgID, "Error: "+err.Error(), false)
		return
	}

	// Ticker chạy mỗi 3 giây để cập nhật tin nhắn (giống setInterval trong Node)
	ticker := time.NewTicker(3 * time.Second)
	stopTicker := make(chan bool)

	go func() {
		for {
			select {
			case <-ticker.C:
				pInfo.Mu.Lock()
				if len(pInfo.Logs) > 0 {
					output := strings.Join(pInfo.Logs, "\n")
					pInfo.Mu.Unlock()
					
					content := fmt.Sprintf("<code>%s</code>\n\n<pre>%s</pre>", 
						html.EscapeString(cmdStr), html.EscapeString(output))
					
					edit := tgbotapi.NewEditMessageText(msg.Chat.ID, targetMsgID, content)
					edit.ParseMode = "HTML"
					markup := stopButton(targetMsgID)
					edit.ReplyMarkup = &markup
					bot.Send(edit)
				} else {
					pInfo.Mu.Unlock()
				}
			case <-stopTicker:
				ticker.Stop()
				return
			}
		}
	}()

	// Chờ lệnh chạy xong
	err := cmd.Wait()
	stopTicker <- true // Dừng ticker cập nhật định kỳ

	// Cleanup cuối cùng (giống hàm cleanup trong Node)
	status := " Success"
	if err != nil {
		status = " Cancel"
	}

	procsMu.Lock()
	delete(activeProcs, targetMsgID)
	procsMu.Unlock()

	finalText := fmt.Sprintf("%s: <code>%s</code>\n\n<b>The process is over.</b>", 
		status, html.EscapeString(cmdStr))
	editMsg(bot, msg.Chat.ID, targetMsgID, finalText, false)
}

// --- Các hàm phụ trợ ---

func handleDocument(bot *tgbotapi.BotAPI, msg *tgbotapi.Message) {
	fileURL, _ := bot.GetFileDirectURL(msg.Document.FileID)
	resp, _ := http.Get(fileURL)
	defer resp.Body.Close()
	out, _ := os.Create(msg.Document.FileName)
	defer out.Close()
	io.Copy(out, resp.Body)
	reply(bot, msg.Chat.ID, fmt.Sprintf(" Saved file: <code>%s</code>", html.EscapeString(msg.Document.FileName)))
}

func handleCallback(bot *tgbotapi.BotAPI, query *tgbotapi.CallbackQuery) {
	if strings.HasPrefix(query.Data, "stop_") {
		msgID, _ := strconv.Atoi(strings.TrimPrefix(query.Data, "stop_"))
		procsMu.Lock()
		pInfo, ok := activeProcs[msgID]
		procsMu.Unlock()
		if ok && pInfo.Cmd.Process != nil {
			syscall.Kill(-pInfo.Cmd.Process.Pid, syscall.SIGKILL)
			pInfo.Cancel()
			bot.Request(tgbotapi.NewCallback(query.ID, "Stopping..."))
		}
	}
}

func stopButton(msgID int) tgbotapi.InlineKeyboardMarkup {
	return tgbotapi.NewInlineKeyboardMarkup(tgbotapi.NewInlineKeyboardRow(
		tgbotapi.NewInlineKeyboardButtonData("Cancel", fmt.Sprintf("stop_%d", msgID)),
	))
}

func reply(bot *tgbotapi.BotAPI, chatID int64, text string) {
	m := tgbotapi.NewMessage(chatID, text)
	m.ParseMode = "HTML"
	bot.Send(m)
}

func editMsg(bot *tgbotapi.BotAPI, chatID int64, msgID int, text string, btn bool) {
	e := tgbotapi.NewEditMessageText(chatID, msgID, text)
	e.ParseMode = "HTML"
	if btn {
		m := stopButton(msgID)
		e.ReplyMarkup = &m
	}
	bot.Send(e)
}
