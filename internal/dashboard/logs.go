package dashboard

import (
	"context"
	"sync"

	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"
)

// LogsTab shows bot logs with live-follow mode.
type LogsTab struct {
	app       *tview.Application
	cfg       *DashboardConfig
	widget    *tview.Flex
	botList   *tview.List
	logView   *tview.TextView
	ctx       context.Context
	cancel    context.CancelFunc
	logsMutex sync.Mutex
	logLines  []string
	follow    bool
	selectedBot int
}

// NewLogsTab creates a new logs tab.
func NewLogsTab() *LogsTab {
	return &LogsTab{
		logLines: make([]string, 0),
		follow:   true,
	}
}

// Widget returns the tab's root widget.
func (l *LogsTab) Widget() tview.Primitive {
	return l.widget
}

// Init initializes the logs tab.
func (l *LogsTab) Init(app *tview.Application, cfg *DashboardConfig) {
	l.app = app
	l.cfg = cfg
	l.ctx, l.cancel = context.WithCancel(context.Background())

	// Bot list (left, 20% width)
	l.botList = tview.NewList()
	l.botList.SetBorder(true).
		SetTitle(" Bots  ↑↓:nav  Enter:select ").
		SetTitleAlign(tview.AlignLeft)

	for _, bot := range cfg.Bots {
		l.botList.AddItem(bot.Name, bot.ReleaseName, 0, nil)
	}

	// Preselect first bot if available
	if len(cfg.Bots) > 0 {
		l.selectedBot = 0
	}

	// Log view (right, 80% width)
	l.logView = tview.NewTextView()
	l.logView.SetBorder(true).
		SetTitleAlign(tview.AlignLeft)
	l.logView.SetDynamicColors(true)
	l.logView.SetInputCapture(l.logInputCapture)

	// Layout: bot list (left) + log view (right)
	flex := tview.NewFlex().
		AddItem(l.botList, 20, 0, true).
		AddItem(l.logView, 0, 1, false)

	l.widget = tview.NewFlex().SetDirection(tview.FlexRow).
		AddItem(flex, 0, 1, true)

	// Bot selection callback
	l.botList.SetSelectedFunc(func(i int, _ string, _ string, _ rune) {
		l.selectedBot = i
		l.loadBotLogs()
	})

	// Load logs for first bot on init
	l.loadBotLogs()
}

// loadBotLogs loads and displays logs for the selected bot.
func (l *LogsTab) loadBotLogs() {
	if l.selectedBot < 0 || l.selectedBot >= len(l.cfg.Bots) {
		return
	}

	bot := l.cfg.Bots[l.selectedBot]
	l.logsMutex.Lock()
	l.logLines = l.logLines[:0] // Clear logs
	l.logsMutex.Unlock()

	// Load initial logs
	logs, err := DockerLogs(bot.ReleaseName, 100)
	if err != nil {
		l.app.QueueUpdateDraw(func() {
			l.logView.SetText("[red]Error loading logs: " + err.Error() + "[-]")
			title := " Logs: " + bot.Name + "  f:follow  q:quit "
			l.logView.SetTitle(title)
		})
		return
	}

	l.logsMutex.Lock()
	if logs != "" {
		l.logLines = append(l.logLines, logs)
	}
	l.logsMutex.Unlock()

	l.app.QueueUpdateDraw(func() {
		l.renderLogs()
	})

	// Start live-follow if enabled
	if l.follow {
		go l.tailLogs(bot.ReleaseName)
	}
}

// tailLogs streams new logs for the selected bot.
func (l *LogsTab) tailLogs(containerName string) {
	logCtx, cancel := context.WithCancel(l.ctx)
	defer cancel()

	callback := func(line string) {
		l.logsMutex.Lock()
		l.logLines = append(l.logLines, line)
		// Keep last 1000 lines in memory
		if len(l.logLines) > 1000 {
			l.logLines = l.logLines[len(l.logLines)-1000:]
		}
		l.logsMutex.Unlock()

		l.app.QueueUpdateDraw(func() {
			l.renderLogs()
		})
	}

	DockerLogsFollow(logCtx, containerName, 100, callback)
}

// renderLogs updates the log view with current log content.
func (l *LogsTab) renderLogs() {
	l.logsMutex.Lock()
	defer l.logsMutex.Unlock()

	if len(l.cfg.Bots) == 0 {
		l.logView.SetText("[dim]No bots selected[-]")
		return
	}

	bot := l.cfg.Bots[l.selectedBot]
	followStr := "follow"
	if !l.follow {
		followStr = "live"
	}

	title := " Logs: " + bot.Name + "  f:" + followStr + "  ↑↓:scroll  q:quit "
	l.logView.SetTitle(title)

	if len(l.logLines) == 0 {
		l.logView.SetText("[dim]No logs yet[-]")
		return
	}

	// Combine all log lines
	logText := ""
	for _, line := range l.logLines {
		logText += line + "\n"
	}

	l.logView.SetText(logText)

	// Auto-scroll to bottom if following
	if l.follow {
		l.logView.ScrollToEnd()
	}
}

// logInputCapture handles key events in the log view.
func (l *LogsTab) logInputCapture(ev *tcell.EventKey) *tcell.EventKey {
	switch ev.Rune() {
	case 'f':
		l.follow = !l.follow
		if l.follow && l.selectedBot >= 0 && l.selectedBot < len(l.cfg.Bots) {
			// Restart tailing when enabling follow
			go l.tailLogs(l.cfg.Bots[l.selectedBot].ReleaseName)
		}
		l.renderLogs()
		return nil
	}
	return ev
}

// Stop stops the logs tab.
func (l *LogsTab) Stop() {
	if l.cancel != nil {
		l.cancel()
	}
}
