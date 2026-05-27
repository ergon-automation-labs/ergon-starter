package dashboard

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/gdamore/tcell/v2"
	"github.com/nats-io/nats.go"
	"github.com/nats-io/nuid"
	"github.com/rivo/tview"
)

const (
	pigoCommandSubject = "pi-go.repl.command.run"
	pigoEventPrefix    = "pi-go.repl.event"
	pigoLLMSubject     = "pi-go.llm.request.chat"
	pigoTurnTimeout    = 120 * time.Second
)

type pigoResult struct {
	ok      bool
	runID   string
	content string
}

type PigoTab struct {
	widget     *tview.Flex
	outputView *tview.TextView
	inputField *tview.InputField
	statusBar  *tview.TextView
	app        *tview.Application
	cfg        *DashboardConfig

	nc     *nats.Conn
	sub    *nats.Subscription
	ctx    context.Context
	cancel context.CancelFunc

	sessionID string
	command   string

	pending   map[string]chan pigoResult
	pendingMu sync.Mutex
}

func NewPigoTab() *PigoTab {
	return &PigoTab{
		pending: make(map[string]chan pigoResult),
		command: "analyze",
	}
}

func (p *PigoTab) Widget() tview.Primitive {
	return p.widget
}

func (p *PigoTab) Init(app *tview.Application, cfg *DashboardConfig) {
	p.app = app
	p.cfg = cfg
	p.ctx, p.cancel = context.WithCancel(context.Background())
	p.sessionID = nuid.New().Next()

	// Output view (scrollable response area)
	p.outputView = tview.NewTextView()
	p.outputView.SetBorder(true).
		SetTitle(" pi-go chat  Enter:send  /help:commands ").
		SetTitleAlign(tview.AlignLeft)
	p.outputView.SetDynamicColors(true)
	p.outputView.SetScrollable(true)
	p.outputView.SetChangedFunc(func() {
		p.app.QueueUpdateDraw(func() {
			p.outputView.ScrollToEnd()
		})
	})

	// Input field (bottom)
	p.inputField = tview.NewInputField()
	p.inputField.SetBorder(true).
		SetTitle(fmt.Sprintf(" %s ", p.command)).
		SetTitleAlign(tview.AlignLeft)
	p.inputField.SetLabel("prompt> ")
	p.inputField.SetFieldWidth(0)

	p.inputField.SetDoneFunc(func(key tcell.Key) {
		if key == tcell.KeyEnter {
			text := strings.TrimSpace(p.inputField.GetText())
			if text == "" {
				return
			}
			p.inputField.SetText("")
			go p.handleInput(text)
		}
	})

	// Help shortcut from input field
	p.inputField.SetInputCapture(func(ev *tcell.EventKey) *tcell.EventKey {
		if ev.Rune() == '?' {
			p.handleSlash("/help")
			return nil
		}
		return ev
	})

	// Status bar — set initial text directly (QueueUpdateDraw deadlocks before app.Run)
	p.statusBar = tview.NewTextView()
	p.statusBar.SetDynamicColors(true)
	p.statusBar.SetText("[red]NATS ○[-]  command: [cyan]analyze[-]  session: [dim]" + shortSessionID(p.sessionID) + "[-]")

	// Layout: output (flex 1) + input (3 rows) + status (1 row)
	p.widget = tview.NewFlex().SetDirection(tview.FlexRow).
		AddItem(p.outputView, 0, 1, false).
		AddItem(p.inputField, 3, 0, true).
		AddItem(p.statusBar, 1, 0, false)

	// Welcome message (NATS connects in Start() to avoid blocking init)
	p.outputView.SetText("[dim]Connecting to NATS...[-]\n")
}

func (p *PigoTab) Start() {
	go p.connectNATS()
}

func (p *PigoTab) Stop() {
	if p.sub != nil {
		p.sub.Unsubscribe()
	}
	if p.nc != nil {
		p.nc.Close()
	}
	if p.cancel != nil {
		p.cancel()
	}
}

func (p *PigoTab) connectNATS() {
	urls := []string{
		fmt.Sprintf("nats://host.docker.internal:%s", p.cfg.NATSPort),
		fmt.Sprintf("nats://localhost:%s", p.cfg.NATSPort),
	}

	for _, url := range urls {
		nc, err := nats.Connect(url, nats.Timeout(3*time.Second), nats.ReconnectWait(2*time.Second))
		if err != nil {
			continue
		}
		p.nc = nc
		break
	}

	if p.nc == nil {
		p.appendOutput("[red]NATS connection failed[-] — chat unavailable until NATS is reachable\n")
		p.app.QueueUpdateDraw(func() { p.updateStatusBar() })
		return
	}

	// Subscribe to repl events
	eventSubject := pigoEventPrefix + ".>"
	sub, err := p.nc.Subscribe(eventSubject, func(msg *nats.Msg) {
		p.handleEvent(msg)
	})
	if err != nil {
		p.appendOutput(fmt.Sprintf("[red]NATS subscribe failed: %s[-]\n", err))
		p.app.QueueUpdateDraw(func() { p.updateStatusBar() })
		return
	}
	p.sub = sub

	p.appendOutput("[cyan]pi-go chat REPL[-]\n")
	p.appendOutput(fmt.Sprintf("NATS: [green]connected[-] port %s  |  session: [dim]%s[-]\n", p.cfg.NATSPort, shortSessionID(p.sessionID)))
	p.appendOutput("[dim]Type a prompt to send to pi-go. /help for commands.[-]\n\n")
	p.app.QueueUpdateDraw(func() { p.updateStatusBar() })
}

func (p *PigoTab) handleInput(text string) {
	// Slash commands
	if strings.HasPrefix(text, "/") {
		p.handleSlash(text)
		return
	}

	// Ensure NATS connection
	if p.nc == nil || !p.nc.IsConnected() {
		p.appendOutput("[yellow]Reconnecting to NATS...[-]\n")
		go p.connectNATS()
		return
	}

	// Generate correlation ID
	corrID := "repl-" + nuid.New().Next()

	// Register pending channel
	replyCh := make(chan pigoResult, 1)
	p.pendingMu.Lock()
	p.pending[corrID] = replyCh
	p.pendingMu.Unlock()

	// Build command envelope
	now := time.Now().UTC().Format(time.RFC3339)
	wallTime := time.Now().Local().Format("15:04:05")
	envelope := map[string]interface{}{
		"event":          "pi-go.command.run",
		"event_id":       nuid.New().Next(),
		"schema_version": "1.0",
		"timestamp":      now,
		"source":         "go.dashboard_pigo",
		"source_node":    "air",
		"triggered_by":  "human",
		"tenant_id":      "dashboard",
		"user_id":        "dashboard#" + p.sessionID,
		"payload": map[string]interface{}{
			"command":        p.command,
			"prompt":         text,
			"correlation_id": corrID,
		},
	}

	payload, _ := json.Marshal(envelope)

	// Dispatch
	err := p.nc.Publish(pigoCommandSubject, payload)
	if err != nil {
		p.pendingMu.Lock()
		delete(p.pending, corrID)
		p.pendingMu.Unlock()
		p.appendOutput(fmt.Sprintf("[red]Publish failed: %s[-]\n", err))
		return
	}

	p.appendOutput(fmt.Sprintf("[yellow]> %s[-]\n", text))
	p.appendOutput(fmt.Sprintf("[dim]dispatched %s (%s) · wall %s[-]\n", shortSessionID(corrID), p.command, wallTime))

	// Wait for result in background
	go func() {
		select {
		case result := <-replyCh:
			p.pendingMu.Lock()
			delete(p.pending, corrID)
			p.pendingMu.Unlock()

			if result.ok {
				p.appendOutput(fmt.Sprintf("\n[green]--- %s complete ---[-]\n", shortSessionID(corrID)))
				p.appendOutput(result.content + "\n\n")
			} else {
				p.appendOutput(fmt.Sprintf("\n[red]--- %s failed ---[-]\n", shortSessionID(corrID)))
				p.appendOutput(fmt.Sprintf("[red]%s[-]\n\n", result.content))
			}
		case <-time.After(pigoTurnTimeout):
			p.pendingMu.Lock()
			delete(p.pending, corrID)
			p.pendingMu.Unlock()
			p.appendOutput(fmt.Sprintf("\n[yellow]--- %s timed out (%s) ---[-]\n\n", shortSessionID(corrID), pigoTurnTimeout))
		case <-p.ctx.Done():
			return
		}
	}()
}

func (p *PigoTab) handleEvent(msg *nats.Msg) {
	var data map[string]interface{}
	if err := json.Unmarshal(msg.Data, &data); err != nil {
		return
	}

	// Extract payload
	payload, ok := mapFromAnyPigo(data["payload"])
	if !ok {
		payload, ok = mapFromAnyPigo(data["Payload"])
	}

	// Extract correlation ID
	var corrID string
	if payload != nil {
		corrID = strings.TrimSpace(stringValPigo(payload["correlation_id"]))
	}
	if corrID == "" {
		corrID = strings.TrimSpace(stringValPigo(data["correlation_id"]))
	}
	if corrID == "" {
		return
	}

	// Determine phase
	phase := eventPhasePigo(data)

	// Progress/start: display inline
	if phase == "started" || phase == "progress" {
		if payload != nil {
			when := time.Now().Local().Format("15:04:05")
			if phase == "started" {
				prompt := strings.TrimSpace(stringValPigo(payload["prompt"]))
				if len(prompt) > 80 {
					prompt = prompt[:77] + "..."
				}
				p.appendOutput(fmt.Sprintf("[dim][%s] agent: run started[-]\n", when))
			} else {
				step := strings.TrimSpace(stringValPigo(payload["step"]))
				var parts []string
				if step != "" {
					parts = append(parts, step)
				}
				if v, ok := numericIntPigo(payload["latency_ms"]); ok && v >= 0 {
					parts = append(parts, fmt.Sprintf("%dms", v))
				}
				if s := strings.TrimSpace(stringValPigo(payload["llm_subject"])); s != "" {
					parts = append(parts, "llm="+s)
				}
				if v, ok := numericIntPigo(payload["tool_round"]); ok && v > 0 {
					parts = append(parts, fmt.Sprintf("round=%d", v))
				}
				if v, ok := numericIntPigo(payload["tool_count"]); ok && v > 0 {
					parts = append(parts, fmt.Sprintf("tools=%d", v))
				}
				if len(parts) == 0 {
					parts = []string{"(progress)"}
				}
				p.appendOutput(fmt.Sprintf("[dim][%s] agent: %s[-]\n", when, strings.Join(parts, " · ")))
			}
		}
		return
	}

	// Completed/failed: deliver to pending channel
	p.pendingMu.Lock()
	ch, exists := p.pending[corrID]
	p.pendingMu.Unlock()

	if !exists || ch == nil {
		return
	}

	switch phase {
	case "completed":
		ch <- pigoResult{
			ok:      true,
			runID:   stringValPigo(payload["run_id"]),
			content: extractReplyPigo(data),
		}
	case "failed":
		content := stringValPigo(payload["error"])
		if content == "" {
			content = stringValPigo(data["error"])
		}
		if content == "" {
			content = extractReplyPigo(data)
		}
		if content == "" {
			content = "run failed"
		}
		ch <- pigoResult{
			ok:      false,
			runID:   stringValPigo(payload["run_id"]),
			content: content,
		}
	}
}

func (p *PigoTab) handleSlash(text string) {
	low := strings.ToLower(text)
	switch low {
	case "/help", "/?", "/h":
		p.appendOutput("[cyan]pi-go chat commands:[-]\n")
		p.appendOutput("  /help          This help\n")
		p.appendOutput("  /status        NATS connection, session, command\n")
		p.appendOutput("  /session new   Start a fresh conversation thread\n")
		p.appendOutput("  /command <n>   Set command: analyze|plan|run|research|autonomous_run|self_request\n")
		p.appendOutput("  /diag          LLM preflight check\n")
		p.appendOutput("  /raw <on|off>   Toggle raw JSON display (coming soon)\n")
		p.appendOutput("\n[dim]Type any other text to send as a prompt to pi-go.[-]\n\n")
	case "/status":
		natsStatus := "[red]disconnected[-]"
		if p.nc != nil && p.nc.IsConnected() {
			natsStatus = "[green]connected[-]"
		}
		p.appendOutput("[cyan]Status[-]\n")
		p.appendOutput(fmt.Sprintf("  NATS:    %s (port %s)\n", natsStatus, p.cfg.NATSPort))
		p.appendOutput(fmt.Sprintf("  session: %s\n", shortSessionID(p.sessionID)))
		p.appendOutput(fmt.Sprintf("  command: %s\n", p.command))
		p.appendOutput("\n")
	case "/session new":
		p.sessionID = nuid.New().Next()
		p.appendOutput(fmt.Sprintf("[green]New session: %s[-]\n\n", shortSessionID(p.sessionID)))
		p.updateStatusBar()
	default:
		if strings.HasPrefix(low, "/command") {
			parts := strings.Fields(text)
			if len(parts) < 2 {
				p.appendOutput("[dim]usage: /command <analyze|plan|run|research|autonomous_run|self_request>[-]\n\n")
				return
			}
			cmd := strings.ToLower(strings.TrimSpace(parts[1]))
			if !allowedPigoCommand(cmd) {
				p.appendOutput(fmt.Sprintf("[red]unknown command %q[-]\n\n", cmd))
				return
			}
			p.command = cmd
			p.appendOutput(fmt.Sprintf("[green]command set to %s[-]\n\n", cmd))
			cmdName := cmd
			p.app.QueueUpdateDraw(func() {
				p.inputField.SetTitle(fmt.Sprintf(" %s ", cmdName))
			})
			p.updateStatusBar()
			return
		}
		if strings.HasPrefix(low, "/diag") {
			p.runDiag()
			return
		}
		p.appendOutput(fmt.Sprintf("[dim]unknown command: %s (try /help)[-]\n\n", text))
	}
}

func (p *PigoTab) runDiag() {
	if p.nc == nil || !p.nc.IsConnected() {
		p.appendOutput("[red]NATS not connected — cannot run /diag[-]\n\n")
		return
	}

	p.appendOutput("[dim]Running LLM preflight check...[-]\n")

	payload := map[string]interface{}{
		"request_id":      nuid.New().Next(),
		"request_type":    "preflight",
		"prompt_context":  map[string]interface{}{"prompt": "diag: reply with the single word ok"},
		"model_preference": "",
		"timeout_ms":      10000,
		"tenant_id":       "dashboard",
	}

	data, _ := json.Marshal(payload)
	msg, err := p.nc.Request(pigoLLMSubject, data, 12*time.Second)
	if err != nil {
		if err == nats.ErrNoResponders {
			p.appendOutput("[red]No responders on pi-go.llm.request.chat[-]\n")
			p.appendOutput("[dim]Is the pi-go agent container running?[-]\n\n")
		} else {
			p.appendOutput(fmt.Sprintf("[red]diag failed: %s[-]\n\n", err))
		}
		return
	}

	var resp map[string]interface{}
	if err := json.Unmarshal(msg.Data, &resp); err != nil {
		p.appendOutput(fmt.Sprintf("[yellow]diag response (raw): %s[-]\n\n", string(msg.Data)))
		return
	}

	content := extractReplyPigo(resp)
	if content != "" {
		p.appendOutput(fmt.Sprintf("[green]LLM responded: %s[-]\n\n", content))
	} else {
		p.appendOutput("[yellow]LLM responded but no text content found[-]\n\n")
	}
}

func (p *PigoTab) appendOutput(text string) {
	p.app.QueueUpdateDraw(func() {
		fmt.Fprint(p.outputView, text)
	})
}

func (p *PigoTab) updateStatusBar() {
	var statusText string
	if p.nc != nil && p.nc.IsConnected() {
		statusText = "[green]NATS ●[-]"
	} else {
		statusText = "[red]NATS ○[-]"
	}
	statusText += fmt.Sprintf("  command: [cyan]%s[-]  session: [dim]%s[-]", p.command, shortSessionID(p.sessionID))
	p.app.QueueUpdateDraw(func() {
		p.statusBar.SetText(statusText)
	})
}

// --- helpers ---

func shortSessionID(id string) string {
	id = strings.TrimSpace(id)
	if len(id) <= 10 {
		return id
	}
	return id[:10] + "…"
}

func mapFromAnyPigo(v interface{}) (map[string]interface{}, bool) {
	if v == nil {
		return nil, false
	}
	m, ok := v.(map[string]interface{})
	return m, ok
}

func stringValPigo(v interface{}) string {
	s, _ := v.(string)
	return s
}

func numericIntPigo(v interface{}) (int, bool) {
	switch n := v.(type) {
	case int:
		return n, true
	case int32:
		return int(n), true
	case int64:
		return int(n), true
	case float64:
		return int(n), true
	default:
		return 0, false
	}
}

func eventPhasePigo(data map[string]interface{}) string {
	ev := strings.TrimSpace(stringValPigo(data["event"]))
	if ev != "" {
		if i := strings.LastIndex(ev, "."); i >= 0 && i < len(ev)-1 {
			k := ev[i+1:]
			switch k {
			case "started", "progress", "completed", "failed":
				return k
			}
		}
	}
	return ""
}

func extractReplyPigo(event map[string]interface{}) string {
	if payload, ok := mapFromAnyPigo(event["payload"]); ok {
		if response, ok := mapFromAnyPigo(payload["llm_response"]); ok {
			if content := strings.TrimSpace(stringValPigo(response["content"])); content != "" {
				return content
			}
		}
		if text := strings.TrimSpace(stringValPigo(payload["reply_text"])); text != "" {
			return text
		}
		if content := strings.TrimSpace(stringValPigo(payload["content"])); content != "" {
			return content
		}
	}
	if text := strings.TrimSpace(stringValPigo(event["reply_text"])); text != "" {
		return text
	}
	if content := strings.TrimSpace(stringValPigo(event["content"])); content != "" {
		return content
	}
	return ""
}

func allowedPigoCommand(cmd string) bool {
	switch cmd {
	case "analyze", "plan", "run", "research", "autonomous_run", "self_request":
		return true
	default:
		return false
	}
}