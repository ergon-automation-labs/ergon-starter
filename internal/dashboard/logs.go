package dashboard

import (
	"context"

	"github.com/rivo/tview"
)

// LogsTab shows bot logs.
type LogsTab struct {
	widget   *tview.Flex
	botList  *tview.List
	logView  *tview.TextView
	ctx      context.Context
	cancel   context.CancelFunc
}

// NewLogsTab creates a new logs tab.
func NewLogsTab() *LogsTab {
	return &LogsTab{}
}

// Widget returns the tab's root widget.
func (l *LogsTab) Widget() tview.Primitive {
	return l.widget
}

// Init initializes the logs tab.
func (l *LogsTab) Init(app *tview.Application, cfg *DashboardConfig) {
	l.ctx, l.cancel = context.WithCancel(context.Background())

	// Bot list (left)
	l.botList = tview.NewList()
	l.botList.SetBorder(true).
		SetTitle(" Bots  ↑↓:nav ").
		SetTitleAlign(tview.AlignLeft)

	for _, bot := range cfg.Bots {
		l.botList.AddItem(bot.Name, bot.ReleaseName, 0, nil)
	}

	// Log view (right)
	l.logView = tview.NewTextView()
	l.logView.SetBorder(true).
		SetTitle(" Log ").
		SetTitleAlign(tview.AlignLeft)
	l.logView.SetDynamicColors(true)

	// Layout
	flex := tview.NewFlex().
		AddItem(l.botList, 0, 1, true).
		AddItem(l.logView, 0, 1, false)

	l.widget = tview.NewFlex().SetDirection(tview.FlexRow).
		AddItem(flex, 0, 1, true)

	// Selection callback
	l.botList.SetSelectedFunc(func(i int, label string, sec string, r rune) {
		if i < len(cfg.Bots) {
			l.logView.SetText("Logs for: " + sec)
		}
	})
}

// Stop stops the logs tab.
func (l *LogsTab) Stop() {
	if l.cancel != nil {
		l.cancel()
	}
}
