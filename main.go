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

func formatOutput(cmdText, logs string) string {
	l := formatLiveLog(logs)
	if l == "" {
		return fmt.Sprintf("<pre>%s</pre>", html.EscapeString(cmdText))
	}
	return fmt.Sprintf("<pre>%s\n\n%s</pre>", html.EscapeString(cmdText), html.EscapeString(l))
}

func formatLiveLog(raw string) string {
	if raw == "" {
		return ""
	}
	lines := strings.Split(raw, "\n")
	var cleaned []string
	for _, line := range lines {
		if strings.TrimSpace(line) != "" {
			cleaned = append(cleaned, line)
		}
	}
	if len(cleaned) == 0 {
		return ""
	}

	lastLine := cleaned[len(cleaned)-1]

	if strings.Contains(lastLine, "\r") {
		parts := strings.Split(lastLine, "\r")
		return strings.TrimSpace(parts[len(parts)-1])
	}

	var finalLines []string
	for _, l := range cleaned {
		if strings.Contains(l, "\r") {
			parts := strings.Split(l, "\r")
			finalLines = append(finalLines, strings.TrimSpace(parts[len(parts)-1]))
		} else {
			finalLines = append(finalLines, strings.TrimSpace(l))
		}
	}

	start := len(finalLines) - 10
	if start < 0 {
		start = 0
	}
	return strings.Join(finalLines[start:], "\n")
}

func main() {
	token, idStr := os.Getenv("tk"), os.Getenv("id")
	adminID, _ = strconv.ParseInt(idStr, 10, 64)
	bot, err := tgbotapi.NewBotAPI(token)
	if err != nil {
		log.Panic(err)
	}
	log.Printf("'.'")

	u := tgbotapi.NewUpdate(0)
	u.Timeout = 60
	updates := bot.GetUpdatesChan(u)

	for update := range updates {
		if update.Message != nil && update.Message.From.ID == adminID {
			if update.Message.Document != nil {
				go handleDocument(bot, update.Message)
			} else if strings.HasPrefix(update.Message.Text, ".") {
				go handleCommand(bot, update.Message)
			}
		} else if update.CallbackQuery != nil {
			go handleCallback(bot, update.CallbackQuery)
		}
	}
}

func handleCommand(bot *tgbotapi.BotAPI, msg *tgbotapi.Message) {
	rawText := msg.Text
	cmdStr := strings.TrimPrefix(rawText, ".")

	sentMsg, _ := bot.Send(tgbotapi.NewMessage(msg.Chat.ID, formatOutput(rawText, "")))
	targetMsgID := sentMsg.MessageID

	bot.Send(tgbotapi.NewEditMessageReplyMarkup(msg.Chat.ID, targetMsgID, stopButton(targetMsgID)))

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

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
				if pInfo.Logs.Len() > 2048 {
					curr := pInfo.Logs.String()
					pInfo.Logs.Reset()
					pInfo.Logs.WriteString(curr[len(curr)-2048:])
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
		editMsg(bot, msg.Chat.ID, targetMsgID, err.Error(), false)
		return
	}

	stopTicker := make(chan bool)
	go func() {
		time.Sleep(1 * time.Second)
		select {
		case <-stopTicker:
			return
		default:
			pInfo.Mu.Lock()
			l := pInfo.Logs.String()
			pInfo.Mu.Unlock()
			editMsg(bot, msg.Chat.ID, targetMsgID, formatOutput(rawText, l), true)
		}

		ticker := time.NewTicker(10 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				pInfo.Mu.Lock()
				l := pInfo.Logs.String()
				pInfo.Mu.Unlock()
				editMsg(bot, msg.Chat.ID, targetMsgID, formatOutput(rawText, l), true)
			case <-stopTicker:
				return
			}
		}
	}()

	_ = cmd.Wait()
	wg.Wait()
	stopTicker <- true

	procsMu.Lock()
	delete(activeProcs, targetMsgID)
	procsMu.Unlock()

	pInfo.Mu.Lock()
	finalLog := pInfo.Logs.String()
	pInfo.Mu.Unlock()

	editMsg(bot, msg.Chat.ID, targetMsgID, formatOutput(rawText, finalLog), false)
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
	reply(bot, msg.Chat.ID, msg.Document.FileName)
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
			bot.Request(tgbotapi.NewCallback(query.ID, "..."))
		} else {
			bot.Request(tgbotapi.NewCallback(query.ID, "Cancel"))
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
