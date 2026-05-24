package dashboard

import (
	"fmt"

	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"
)

// DashboardConfig holds the configuration for the dashboard.
type DashboardConfig struct {
	NATSPort     string
	PostgresPort string
	Bots         []BotInfo
	DataDir      string // "./data/logs/"
}

// BotInfo describes a bot service.
type BotInfo struct {
	Name        string // "gtd"
	ReleaseName string // "gtd_bot" (container name)
	Repo        string // "bot_army_gtd"
}

// Dashboard is the main dashboard application.
type Dashboard struct {
	app    *tview.Application
	cfg    *DashboardConfig
	header *tview.TextView
	status *tview.TextView
	pages  *tview.Pages
	root   *tview.Flex

	fleet  *FleetTab
	logs   *LogsTab
	nats   *NATSTab
	system *SystemTab

	activeTab string
}

// NewDashboard creates a new dashboard.
func NewDashboard(cfg *DashboardConfig) *Dashboard {
	return &Dashboard{
		app:       tview.NewApplication(),
		cfg:       cfg,
		activeTab: "fleet",
	}
}

// Run starts the dashboard and blocks until the user quits.
func (d *Dashboard) Run() error {
	d.buildLayout()
	d.initTabs()
	d.setupKeyCapture()

	if err := d.app.Run(); err != nil {
		return err
	}

	d.stopTabs()
	return nil
}

// buildLayout creates the root layout: header + pages + status.
func (d *Dashboard) buildLayout() {
	// Header
	d.header = tview.NewTextView()
	d.header.SetDynamicColors(true)
	d.updateHeader()

	// Status bar
	d.status = tview.NewTextView()
	d.status.SetDynamicColors(true)
	d.setStatus("Initializing...")

	// Pages container for tabs
	d.pages = tview.NewPages()

	// Root layout
	d.root = tview.NewFlex().SetDirection(tview.FlexRow).
		AddItem(d.header, 1, 0, false).
		AddItem(d.pages, 0, 1, true).
		AddItem(d.status, 1, 0, false)

	d.app.SetRoot(d.root, true)
}

// initTabs initializes all 4 tabs.
func (d *Dashboard) initTabs() {
	d.fleet = NewFleetTab()
	d.fleet.Init(d.app, d.cfg)

	d.logs = NewLogsTab()
	d.logs.Init(d.app, d.cfg)

	d.nats = NewNATSTab()
	d.nats.Init(d.app, d.cfg)

	d.system = NewSystemTab()
	d.system.Init(d.app, d.cfg)

	// Add pages in order
	d.pages.AddPage("fleet", d.fleet.Widget(), true, true)
	d.pages.AddPage("logs", d.logs.Widget(), true, false)
	d.pages.AddPage("nats", d.nats.Widget(), true, false)
	d.pages.AddPage("system", d.system.Widget(), true, false)

	// Start the fleet tab first
	d.app.SetFocus(d.fleet.Widget())
}

// stopTabs stops all background goroutines in tabs.
func (d *Dashboard) stopTabs() {
	d.fleet.Stop()
	d.logs.Stop()
	d.nats.Stop()
	d.system.Stop()
}

// setupKeyCapture sets up global key bindings.
func (d *Dashboard) setupKeyCapture() {
	d.app.SetInputCapture(func(ev *tcell.EventKey) *tcell.EventKey {
		switch ev.Rune() {
		case '1':
			d.switchTab("fleet", d.fleet.Widget())
			return nil
		case '2':
			d.switchTab("logs", d.logs.Widget())
			return nil
		case '3':
			d.switchTab("nats", d.nats.Widget())
			return nil
		case '4':
			d.switchTab("system", d.system.Widget())
			return nil
		case 'q':
			d.app.Stop()
			return nil
		}

		// Tab key: cycle through tabs
		switch ev.Key() {
		case tcell.KeyTab:
			switch d.activeTab {
			case "fleet":
				d.switchTab("logs", d.logs.Widget())
			case "logs":
				d.switchTab("nats", d.nats.Widget())
			case "nats":
				d.switchTab("system", d.system.Widget())
			case "system":
				d.switchTab("fleet", d.fleet.Widget())
			}
			return nil

		case tcell.KeyBacktab: // Shift+Tab
			switch d.activeTab {
			case "fleet":
				d.switchTab("system", d.system.Widget())
			case "logs":
				d.switchTab("fleet", d.fleet.Widget())
			case "nats":
				d.switchTab("logs", d.logs.Widget())
			case "system":
				d.switchTab("nats", d.nats.Widget())
			}
			return nil
		}

		return ev
	})
}

// switchTab switches to the given tab.
func (d *Dashboard) switchTab(name string, widget tview.Primitive) {
	d.activeTab = name
	d.pages.SwitchToPage(name)
	d.updateHeader()
	d.app.SetFocus(widget)
}

// updateHeader updates the header with the current tab.
func (d *Dashboard) updateHeader() {
	tabs := []string{"fleet", "logs", "nats", "system"}
	header := "🤖 Bot Army  "

	for _, tab := range tabs {
		if tab == d.activeTab {
			header += fmt.Sprintf("[yellow][%s][-] ", tab)
		} else {
			header += fmt.Sprintf("[%s] ", tab)
		}
	}

	header += "  q:quit"
	d.header.SetText(header)
}

// setStatus updates the status bar.
func (d *Dashboard) setStatus(msg string) {
	d.status.SetText(msg)
}

// RunFromConfig launches the dashboard with a wizard Config.
// Note: This requires importing the wizard package; kept minimal to avoid cycles.
func RunFromWizardConfig(natsPort string, botNames []string, botReleaseNames []string, dataDir string) error {
	bots := make([]BotInfo, len(botNames))
	for i, name := range botNames {
		releaseName := botReleaseNames[i]
		bots[i] = BotInfo{
			Name:        name,
			ReleaseName: releaseName,
		}
	}

	cfg := &DashboardConfig{
		NATSPort: natsPort,
		Bots:     bots,
		DataDir:  dataDir,
	}

	d := NewDashboard(cfg)
	return d.Run()
}

// RunFromDir launches the dashboard from a directory with .env and docker-compose.yml.
func RunFromDir(dir string) error {
	cfg, err := DashboardConfigFromEnv(dir)
	if err != nil {
		return err
	}

	d := NewDashboard(cfg)
	return d.Run()
}
