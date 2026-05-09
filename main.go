package main

import (
	"context"
	"fmt"
	"html"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api/v5"
)

var ansiRegex = regexp.MustCompile(`\x1b\[[0-9;]*[a-zA-Z]`)

type ProcInfo struct {
	Cmd    *exec.Cmd
	Logs   strings.Builder
	Mu     sync.Mutex
	Cancel context.CancelFunc
}

var (
	activeProcs = make(map[int]*ProcInfo)
	procsMu     sync.Mutex
	adminID     int64
)

func formatLiveLog(raw string) string {
	if raw == "" {
		return "Executing..."
	}
	lines := strings.Split(raw, "\n")
	var lastLine string

	for i := len(lines) - 1; i >= 0; i-- {
		if strings.TrimSpace(lines[i]) != "" {
			lastLine = lines[i]
			break
		}
	}

	if strings.Contains(lastLine, "\r") {
		parts := strings.Split(lastLine, "\r")
		lastLine = parts[len(parts)-1]
	}

	return strings.TrimSpace(lastLine)
}

func main() {
	token := os.Getenv("TK")
	idStr := os.Getenv("ID")
	adminID, _ = strconv.ParseInt(idStr, 10, 64)

	bot, err := tgbotapi.NewBotAPI(token)
	if err != nil {
		log.Panic(err)
	}

	log.Printf("Bot Go is ready and listening for commands starting with '.'")

	u := tgbotapi.NewUpdate(0)
	u.Timeout = 60
	updates := bot.GetUpdatesChan(u)

	for update := range updates {
		if update.Message != nil && update.Message.From.ID == adminID {
			if update.Message.Document != nil {
				go handleDocument(bot, update.Message)
			} else if strings.HasPrefix(update.Message.Text, ".") { // Chỉ nhận lệnh bắt đầu bằng dấu chấm
				go handleCommand(bot, update.Message)
			}
		} else if update.CallbackQuery != nil {
			go handleCallback(bot, update.CallbackQuery)
		}
	}
}

func handleCommand(bot *tgbotapi.BotAPI, msg *tgbotapi.Message) {
	// Loại bỏ dấu chấm ở đầu để thực thi lệnh
	cmdStr := strings.TrimPrefix(msg.Text, ".")

	sentMsg, _ := bot.Send(tgbotapi.NewMessage(msg.Chat.ID, fmt.Sprintf("<b>Running:</b> <code>%s</code>", html.EscapeString(cmdStr))))
	targetMsgID := sentMsg.MessageID

	editMarkup := tgbotapi.NewEditMessageReplyMarkup(msg.Chat.ID, targetMsgID, stopButton(targetMsgID))
	bot.Send(editMarkup)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Sử dụng stdbuf để bắt log ngay lập tức
	cmd := exec.CommandContext(ctx, "sh", "-c", "stdbuf -oL -eL "+cmdStr)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	stdout, _ := cmd.StdoutPipe()
	stderr, _ := cmd.StderrPipe()

	pInfo := &ProcInfo{Cmd: cmd, Cancel: cancel}
	procsMu.Lock()
	activeProcs[targetMsgID] = pInfo
	procsMu.Unlock()

	var wg sync.WaitGroup
	wg.Add(2)

	readToLogs := func(r io.Reader) {
		defer wg.Done()
		buf := make([]byte, 1024)
		for {
			n, err := r.Read(buf)
			if n > 0 {
				cleanStr := ansiRegex.ReplaceAllString(string(buf[:n]), "")
				pInfo.Mu.Lock()
				pInfo.Logs.WriteString(cleanStr)
				// Giới hạn log tránh tràn message Telegram
				if pInfo.Logs.Len() > 3800 {
					current := pInfo.Logs.String()
					pInfo.Logs.Reset()
					pInfo.Logs.WriteString(current[len(current)-3800:])
				}
				pInfo.Mu.Unlock()
			}
			if err != nil {
				break
			}
		}
	}

	go readToLogs(stdout)
	go readToLogs(stderr)

	if err := cmd.Start(); err != nil {
		editMsg(bot, msg.Chat.ID, targetMsgID, "Error: "+err.Error(), false)
		return
	}

	ticker := time.NewTicker(2 * time.Second) // Cập nhật nhanh hơn (2s thay vì 10s)
	defer ticker.Stop()
	stopTicker := make(chan bool)

	go func() {
		for {
			select {
			case <-ticker.C:
				pInfo.Mu.Lock()
				logData := pInfo.Logs.String()
				currentLog := formatLiveLog(logData)
				pInfo.Mu.Unlock()

				content := fmt.Sprintf("<b>Cmd:</b> <code>%s</code>\n<pre>%s</pre>",
					html.EscapeString(cmdStr), html.EscapeString(currentLog))

				edit := tgbotapi.NewEditMessageText(msg.Chat.ID, targetMsgID, content)
				edit.ParseMode = "HTML"
				markup := stopButton(targetMsgID)
				edit.ReplyMarkup = &markup
				bot.Send(edit)
			case <-stopTicker:
				return
			}
		}
	}()

	_ = cmd.Wait()
	wg.Wait() // Đợi toàn bộ log được đọc xong từ Pipe trước khi đóng
	stopTicker <- true

	procsMu.Lock()
	delete(activeProcs, targetMsgID)
	procsMu.Unlock()

	pInfo.Mu.Lock()
	finalLog := pInfo.Logs.String()
	if finalLog == "" {
		finalLog = "Command finished with no output."
	} else {
		// Lấy đoạn log cuối cùng cho gọn, hoặc để nguyên tùy nhu cầu
		finalLog = formatLiveLog(finalLog)
	}
	pInfo.Mu.Unlock()

	finalText := fmt.Sprintf("<b>Done:</b> <code>%s</code>\n<pre>%s</pre>",
		html.EscapeString(cmdStr), html.EscapeString(finalLog))

	editMsg(bot, msg.Chat.ID, targetMsgID, finalText, false)
}

func handleDocument(bot *tgbotapi.BotAPI, msg *tgbotapi.Message) {
	fileURL, _ := bot.GetFileDirectURL(msg.Document.FileID)
	resp, err := http.Get(fileURL)
	if err != nil {
		return
	}
	defer resp.Body.Close()

	out, err := os.Create(msg.Document.FileName)
	if err != nil {
		return
	}
	defer out.Close()

	io.Copy(out, resp.Body)
	reply(bot, msg.Chat.ID, "Saved file: "+msg.Document.FileName)
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
			bot.Request(tgbotapi.NewCallback(query.ID, "Process Terminated."))
		} else {
			bot.Request(tgbotapi.NewCallback(query.ID, "Process not found or finished."))
		}
	}
}

func stopButton(msgID int) tgbotapi.InlineKeyboardMarkup {
	return tgbotapi.NewInlineKeyboardMarkup(tgbotapi.NewInlineKeyboardRow(
		tgbotapi.NewInlineKeyboardButtonData("⏹ Stop", fmt.Sprintf("stop_%d", msgID)),
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
