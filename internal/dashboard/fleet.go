package dashboard

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"
)

// FleetTab shows running bots and their status.
type FleetTab struct {
	widget     *tview.Flex
	botList    *tview.List
	botDetail  *tview.TextView
	app        *tview.Application
	cfg        *DashboardConfig
	containers map[string]DockerContainer
	healthMon  *NATSHealthMonitor
	selected   string
	ctx        context.Context
	cancel     context.CancelFunc
}

// NewFleetTab creates a new fleet tab.
func NewFleetTab() *FleetTab {
	return &FleetTab{
		containers: make(map[string]DockerContainer),
	}
}

// Widget returns the tab's root widget.
func (f *FleetTab) Widget() tview.Primitive {
	return f.widget
}

// Init initializes the fleet tab.
func (f *FleetTab) Init(app *tview.Application, cfg *DashboardConfig) {
	f.app = app
	f.cfg = cfg
	f.ctx, f.cancel = context.WithCancel(context.Background())

	// Bot list (left panel)
	f.botList = tview.NewList()
	f.botList.SetBorder(true).
		SetTitle(fmt.Sprintf(" Bots (:%s)  ↑↓:nav  Enter:details ", cfg.NATSPort)).
		SetTitleAlign(tview.AlignLeft)

	// Bot detail (right panel)
	f.botDetail = tview.NewTextView()
	f.botDetail.SetBorder(true).
		SetTitle(" Details ").
		SetTitleAlign(tview.AlignLeft)
	f.botDetail.SetDynamicColors(true)

	// Layout: left list + right detail
	flex := tview.NewFlex().
		AddItem(f.botList, 0, 1, true).
		AddItem(f.botDetail, 0, 1, false)

	f.widget = tview.NewFlex().SetDirection(tview.FlexRow).
		AddItem(flex, 0, 1, true)

	// List selection callback
	f.botList.SetSelectedFunc(func(i int, label string, sec string, r rune) {
		if i < len(f.cfg.Bots) {
			f.selected = f.cfg.Bots[i].ReleaseName
			f.updateDetail()
		}
	})

	// Input capture for keys
	f.botList.SetInputCapture(func(ev *tcell.EventKey) *tcell.EventKey {
		switch ev.Rune() {
		case 'r':
			// Restart selected bot
			if f.selected != "" {
				f.app.QueueUpdateDraw(func() {
					f.botDetail.SetText(fmt.Sprintf("[yellow]Restarting %s...[-]", f.selected))
				})
			}
			return nil
		}
		return ev
	})

	// Start NATS health monitor
	f.healthMon = NewNATSHealthMonitor(cfg.NATSPort)
}

// Start triggers the initial data fetch (called after tview event loop starts).
func (f *FleetTab) Start() {
	go f.refreshLoop()
}

// refreshLoop periodically refreshes the fleet list.
func (f *FleetTab) refreshLoop() {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-f.ctx.Done():
			return
		case <-ticker.C:
			f.refresh()
		}
	}
}

// refresh gets the current container list and NATS health, then updates the UI.
func (f *FleetTab) refresh() {
	containers, err := DockerPS()
	if err != nil {
		f.app.QueueUpdateDraw(func() {
			f.botList.Clear()
			f.botList.AddItem("[red]Docker not running[-]", "", 0, nil)
		})
		return
	}

	// Build map of containers keyed by compose service name.
	contMap := make(map[string]DockerContainer)
	for _, c := range containers {
		contMap[c.Names] = c
	}

	// Try to connect/reconnect NATS health monitor (async, don't block)
	if f.healthMon != nil {
		go f.healthMon.Connect()
	}

	// Get cached health status
	var health map[string]HealthStatus
	natsConnected := false
	if f.healthMon != nil {
		health = f.healthMon.GetHealth()
		natsConnected = f.healthMon.Connected()
	}

	f.app.QueueUpdateDraw(func() {
		f.botList.Clear()
		f.containers = contMap

		// Show NATS connection status
		if !natsConnected {
			f.botDetail.SetText("[yellow]NATS not connected[-]\n\nHealth beacons require a running NATS server.\nEnsure bots are running and NATS is reachable on port " + f.cfg.NATSPort + ".")
		}

		for _, bot := range f.cfg.Bots {
			cont, hasContainer := contMap[bot.ReleaseName]
			h, hasHealth := MatchService(health, bot.ReleaseName)

			var label string
			if !hasContainer && len(f.cfg.Bots) == 0 {
				// No bots configured — skip
				continue
			} else if !hasContainer {
				label = fmt.Sprintf("○ %s  [red]not found[-]", bot.Name)
			} else {
				var icon, color, statusText string
				if hasHealth && h.Status == "healthy" {
					icon = "●"
					color = "[green]"
					statusText = h.Status
				} else if hasHealth && h.Status == "degraded" {
					icon = "◐"
					color = "[yellow]"
					statusText = h.Status
				} else if strings.Contains(cont.State, "running") {
					icon = "◐"
					color = "[yellow]"
					statusText = "running"
				} else if strings.Contains(cont.State, "exited") {
					icon = "○"
					color = "[red]"
					statusText = cont.State
				} else {
					icon = "◐"
					color = "[yellow]"
					statusText = cont.State
				}
				label = fmt.Sprintf("%s %s  %s%s[-]", icon, bot.Name, color, statusText)
			}

			f.botList.AddItem(label, bot.ReleaseName, 0, nil)
		}

		// Set first bot as selected if none selected yet
		if f.selected == "" && len(f.cfg.Bots) > 0 {
			f.selected = f.cfg.Bots[0].ReleaseName
		}

		// If no bots configured, auto-discover from Docker containers
		if len(f.cfg.Bots) == 0 && len(containers) > 0 {
			for _, c := range containers {
				name := ComposeServiceName(c.Names)
				if name == "nats" || name == "postgres" || name == "ollama" {
					continue
				}
				label := fmt.Sprintf("◐ %s  [yellow]%s[-]", name, c.State)
				f.botList.AddItem(label, name, 0, nil)
			}
			if f.botList.GetItemCount() == 0 {
				f.botList.AddItem("[dim]No services found[-]", "", 0, nil)
			}
			f.botDetail.SetText("[dim]No .env or docker-compose.yml found.\nServices discovered from Docker.[-]")
		}

		f.updateDetail()
	})
}

// updateDetail updates the detail panel for the selected bot.
func (f *FleetTab) updateDetail() {
	cont, hasContainer := f.containers[f.selected]
	h, hasHealth := MatchService(f.healthMon.GetHealth(), f.selected)

	if !hasContainer {
		f.botDetail.SetText("[red]Container not found[-]")
		return
	}

	detail := fmt.Sprintf("[cyan]%s[-]\n\n", f.selected)

	if hasHealth {
		detail += fmt.Sprintf("NATS: [green]%s[-]\n", h.Status)
		detail += fmt.Sprintf("Uptime: %s\n", formatUptime(h.Uptime))
	}

	detail += fmt.Sprintf("\nContainer: %s\n", cont.State)
	detail += fmt.Sprintf("Status: %s\n", cont.Status)
	detail += fmt.Sprintf("Image: %s\n", cont.Image)
	if cont.Ports != "" {
		detail += fmt.Sprintf("Ports: %s\n", cont.Ports)
	}
	detail += fmt.Sprintf("Created: %s\n", cont.Created)

	f.botDetail.SetText(detail)
}

// formatUptime formats seconds into a human-readable duration.
func formatUptime(seconds int) string {
	if seconds < 60 {
		return fmt.Sprintf("%ds", seconds)
	}
	if seconds < 3600 {
		return fmt.Sprintf("%dm", seconds/60)
	}
	if seconds < 86400 {
		return fmt.Sprintf("%dh%dm", seconds/3600, (seconds%3600)/60)
	}
	return fmt.Sprintf("%dd%dh", seconds/86400, (seconds%86400)/3600)
}

// Stop stops the fleet tab's background tasks.
func (f *FleetTab) Stop() {
	if f.healthMon != nil {
		f.healthMon.Close()
	}
	if f.cancel != nil {
		f.cancel()
	}
}