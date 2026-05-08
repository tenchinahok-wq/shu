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
	Logs   string
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
		return ""
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

	log.Printf("Bot Go is ready...")

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
	sentMsg, _ := bot.Send(tgbotapi.MessageConfig{
		BaseChat: tgbotapi.BaseChat{
			ChatID:      msg.Chat.ID,
			ReplyMarkup: stopButton(msg.MessageID + 1),
		},
		Text:      fmt.Sprintf("<pre>%s</pre>", html.EscapeString(cmdStr)),
		ParseMode: "HTML",
	})

	targetMsgID := sentMsg.MessageID
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel() 
	
	cmd := exec.CommandContext(ctx, "sh", "-c", "stdbuf -oL -eL "+cmdStr)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	stdout, _ := cmd.StdoutPipe()
	stderr, _ := cmd.StderrPipe()

	pInfo := &ProcInfo{Cmd: cmd, Logs: "", Cancel: cancel}
	procsMu.Lock()
	activeProcs[targetMsgID] = pInfo
	procsMu.Unlock()

	readToLogs := func(r io.Reader) {
		buf := make([]byte, 1024)
		for {
			n, err := r.Read(buf)
			if n > 0 {
				cleanStr := ansiRegex.ReplaceAllString(string(buf[:n]), "")
				pInfo.Mu.Lock()
				pInfo.Logs += cleanStr
				if len(pInfo.Logs) > 4096 {
					pInfo.Logs = pInfo.Logs[len(pInfo.Logs)-4096:]
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

	ticker := time.NewTicker(2 * time.Second) 
	defer ticker.Stop()
	
	stopTicker := make(chan bool)

	go func() {
		for {
			select {
			case <-ticker.C:
				pInfo.Mu.Lock()
				currentLog := formatLiveLog(pInfo.Logs)
				pInfo.Mu.Unlock()

				if currentLog != "" {
					content := fmt.Sprintf("<pre>%s\n\n%s</pre>", 
						html.EscapeString(cmdStr), html.EscapeString(currentLog))
					
					edit := tgbotapi.NewEditMessageText(msg.Chat.ID, targetMsgID, content)
					edit.ParseMode = "HTML"
					markup := stopButton(targetMsgID)
					edit.ReplyMarkup = &markup
					bot.Send(edit)
				}
			case <-stopTicker:
				return
			}
		}
	}()

	_ = cmd.Wait() 
	stopTicker <- true

	procsMu.Lock()
	delete(activeProcs, targetMsgID)
	procsMu.Unlock()

	pInfo.Mu.Lock()
	finalLog := formatLiveLog(pInfo.Logs)
	pInfo.Mu.Unlock()

	finalText := fmt.Sprintf("<pre>%s\n\n%s</pre>", 
		html.EscapeString(cmdStr), html.EscapeString(finalLog))
	
	editMsg(bot, msg.Chat.ID, targetMsgID, finalText, false)
}

func handleDocument(bot *tgbotapi.BotAPI, msg *tgbotapi.Message) {
	fileURL, _ := bot.GetFileDirectURL(msg.Document.FileID)
	resp, err := http.Get(fileURL)
	if err != nil { return }
	defer resp.Body.Close()
	
	out, err := os.Create(msg.Document.FileName)
	if err != nil { return }
	defer out.Close()
	
	io.Copy(out, resp.Body)
	reply(bot, msg.Chat.ID, "Saved: "+msg.Document.FileName)
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
			bot.Request(tgbotapi.NewCallback(query.ID, "Cancel..."))
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
