package dashboard

import (
	"context"
	"time"

	"github.com/rivo/tview"
)

// SystemTab shows system resource usage.
type SystemTab struct {
	widget *tview.Table
	app    *tview.Application
	cfg    *DashboardConfig
	ctx    context.Context
	cancel context.CancelFunc
}

// NewSystemTab creates a new system tab.
func NewSystemTab() *SystemTab {
	return &SystemTab{}
}

// Widget returns the tab's root widget.
func (s *SystemTab) Widget() tview.Primitive {
	return s.widget
}

// Init initializes the system tab.
func (s *SystemTab) Init(app *tview.Application, cfg *DashboardConfig) {
	s.app = app
	s.cfg = cfg
	s.ctx, s.cancel = context.WithCancel(context.Background())

	// Table for stats
	s.widget = tview.NewTable()
	s.widget.SetBorder(true).
		SetTitle(" System Stats  r:refresh ").
		SetTitleAlign(tview.AlignLeft)

	// Header row
	headers := []string{"Container", "CPU%", "Memory", "Net I/O", "Block I/O"}
	for i, h := range headers {
		cell := tview.NewTableCell(h)
		cell.SetTextColor(3) // Yellow
		s.widget.SetCell(0, i, cell)
	}
}

// Start triggers the initial data fetch (called after tview event loop starts).
func (s *SystemTab) Start() {
	go s.refreshLoop()
}

// refreshLoop periodically refreshes stats.
func (s *SystemTab) refreshLoop() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-s.ctx.Done():
			return
		case <-ticker.C:
			s.refresh()
		}
	}
}

// refresh updates the stats table.
func (s *SystemTab) refresh() {
	stats, err := DockerStats()
	if err != nil {
		return
	}

	s.app.QueueUpdateDraw(func() {
		// Clear existing rows (keep header)
		for row := s.widget.GetRowCount(); row > 1; row-- {
			s.widget.RemoveRow(row - 1)
		}

		// Add stat rows
		for i, stat := range stats {
			row := i + 1
			s.widget.SetCell(row, 0, tview.NewTableCell(stat.Name))
			s.widget.SetCell(row, 1, tview.NewTableCell(stat.CPUPerc))
			s.widget.SetCell(row, 2, tview.NewTableCell(stat.MemUsage))
			s.widget.SetCell(row, 3, tview.NewTableCell(stat.NetIO))
			s.widget.SetCell(row, 4, tview.NewTableCell(stat.BlockIO))
		}
	})
}

// Stop stops the system tab.
func (s *SystemTab) Stop() {
	if s.cancel != nil {
		s.cancel()
	}
}
