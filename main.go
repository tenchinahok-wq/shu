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
	"os/signal"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api/v5"
)

var (
	ansiRegex     = regexp.MustCompile(`\x1b\[[0-9;]*[a-zA-Z]`)
	activeProcs   = make(map[int]*ProcInfo)
	procsMu       sync.Mutex
	adminID       int64
	jobSemaphore  = make(chan struct{}, 3) 
)

type ProcInfo struct {
	Cmd    *exec.Cmd
	Logs   strings.Builder
	Mu     sync.Mutex
	Cancel context.CancelFunc
}

func isMultiLineCmd(cmd string) bool {
	cmd = strings.ToLower(strings.Fields(cmd)[0])
	systemPrefixes := map[string]bool{
		"ls": true, "apt": true, "npm": true, "python": true,
		"cat": true, "df": true, "ps": true, "netstat": true, "find": true, "grep": true,
	}
	return systemPrefixes[cmd]
}

func isDangerous(cmd string) bool {
	cmd = strings.ToLower(cmd)
	dangerZone := []string{"rm -rf /", "mkfs", ":(){ :|:& };:", "dd if=", "shutdown", "reboot"}
	for _, d := range dangerZone {
		if strings.Contains(cmd, d) {
			return true
		}
	}
	return false
}

func formatLiveLog(raw string, multiLine bool) string {
	if raw == "" { return "" }
	lines := strings.Split(raw, "\n")
	var cleaned []string

	for _, line := range lines {
		if strings.Contains(line, "\r") {
			parts := strings.Split(line, "\r")
			line = parts[len(parts)-1]
		}
		if t := strings.TrimSpace(line); t != "" {
			cleaned = append(cleaned, t)
		}
	}

	if len(cleaned) == 0 { return "" }
	if multiLine {
		if len(cleaned) > 10 { cleaned = cleaned[len(cleaned)-10:] }
		return strings.Join(cleaned, "\n")
	}
	return cleaned[len(cleaned)-1]
}

func main() {
	token := os.Getenv("TK")
	idStr := os.Getenv("ID")
	adminID, _ = strconv.ParseInt(idStr, 10, 64)

	bot, err := tgbotapi.NewBotAPI(token)
	if err != nil { log.Panic(err) }

	log.Printf("%s", bot.Self.UserName)

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigChan
		procsMu.Lock()
		for _, p := range activeProcs {
			if p.Cmd != nil && p.Cmd.Process != nil {
				syscall.Kill(-p.Cmd.Process.Pid, syscall.SIGKILL)
			}
			p.Cancel()
		}
		os.Exit(0)
	}()

	u := tgbotapi.NewUpdate(0)
	u.Timeout = 60
	updates := bot.GetUpdatesChan(u)

	for update := range updates {
		if update.Message != nil && update.Message.From.ID == adminID {
			if update.Message.Text != "" {
				go handleCommand(bot, update.Message)
			} else if update.Message.Document != nil {
				go handleDocument(bot, update.Message)
			}
		} else if update.CallbackQuery != nil {
			go handleCallback(bot, update.CallbackQuery)
		}
	}
}

func handleCommand(bot *tgbotapi.BotAPI, msg *tgbotapi.Message) {
	defer func() { recover() }()

	cmdStr := msg.Text
	if isDangerous(cmdStr) {
		reply(bot, msg.Chat.ID, "Cancel")
		return
	}

	select {
	case jobSemaphore <- struct{}{}:
		defer func() { <-jobSemaphore }()
	default:
		reply(bot, msg.Chat.ID, "Max conns")
		return
	}

	isMulti := isMultiLineCmd(cmdStr)
	sentMsg, err := bot.Send(tgbotapi.NewMessage(msg.Chat.ID, "<i>Starting...</i>"))
	if err != nil { return }

	targetMsgID := sentMsg.MessageID
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

	readToLogs := func(rc io.ReadCloser) {
		defer rc.Close()
		buf := make([]byte, 1024)
		for {
			n, err := rc.Read(buf)
			if n > 0 {
				clean := ansiRegex.ReplaceAllString(string(buf[:n]), "")
				pInfo.Mu.Lock()
				if pInfo.Logs.Len() > 5000 {
					oldLogs := pInfo.Logs.String()
					pInfo.Logs.Reset()
					pInfo.Logs.WriteString(oldLogs[len(oldLogs)-2000:])
				}
				pInfo.Logs.WriteString(clean)
				pInfo.Mu.Unlock()
			}
			if err != nil { break }
		}
	}

	go readToLogs(stdout)
	go readToLogs(stderr)

	if err := cmd.Start(); err != nil {
		editMsg(bot, msg.Chat.ID, targetMsgID, "Error: "+err.Error(), false)
		return
	}

	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()
	var lastSent string

	updateLoop:
	for {
		select {
		case <-ticker.C:
			pInfo.Mu.Lock()
			current := formatLiveLog(pInfo.Logs.String(), isMulti)
			pInfo.Mu.Unlock()

			if current != "" {
				newMsg := fmt.Sprintf("<pre>%s\n\n%s</pre>", html.EscapeString(cmdStr), html.EscapeString(current))
				if newMsg != lastSent && len(newMsg) < 4000 {
					edit := tgbotapi.NewEditMessageText(msg.Chat.ID, targetMsgID, newMsg)
					edit.ParseMode = "HTML"
					markup := stopButton(targetMsgID)
					edit.ReplyMarkup = &markup
					bot.Send(edit)
					lastSent = newMsg
				}
			}
		case <-ctx.Done():
			break updateLoop
		}
		
		if cmd.ProcessState != nil || ctx.Err() != nil { break }
		time.Sleep(100 * time.Millisecond)
	}

	cmd.Wait()
	procsMu.Lock()
	delete(activeProcs, targetMsgID)
	procsMu.Unlock()

	pInfo.Mu.Lock()
	final := formatLiveLog(pInfo.Logs.String(), isMulti)
	pInfo.Mu.Unlock()

	finalText := fmt.Sprintf("<pre>%s\n\n%s</pre>", html.EscapeString(cmdStr), html.EscapeString(final))
	editMsg(bot, msg.Chat.ID, targetMsgID, finalText, false)
}

func handleDocument(bot *tgbotapi.BotAPI, msg *tgbotapi.Message) {
	fileURL, _ := bot.GetFileDirectURL(msg.Document.FileID)
	resp, _ := http.Get(fileURL)
	defer resp.Body.Close()
	out, _ := os.Create(msg.Document.FileName)
	defer out.Close()
	io.Copy(out, resp.Body)
	reply(bot, msg.Chat.ID, "Saved: <code>"+msg.Document.FileName+"</code>")
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
	m := tgbotapi.NewMessage(chatID, text); m.ParseMode = "HTML"; bot.Send(m)
}

func editMsg(bot *tgbotapi.BotAPI, chatID int64, msgID int, text string, btn bool) {
	e := tgbotapi.NewEditMessageText(chatID, msgID, text); e.ParseMode = "HTML"
	if btn { m := stopButton(msgID); e.ReplyMarkup = &m }
	bot.Send(e)
}
