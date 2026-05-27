package dashboard

import (
	"fmt"
	"os"
	"time"

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
	pigo   *PigoTab

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
	fmt.Fprintln(os.Stderr, "bot-army: starting dashboard...")
	d.buildLayout()
	d.initTabs()
	d.setupKeyCapture()

	// Schedule initial data fetches for after the event loop starts.
	// The brief delay ensures app.Run() has started the tview event loop
	// before QueueUpdateDraw is called, avoiding the Init-time deadlock.
	go func() {
		time.Sleep(100 * time.Millisecond)
		d.fleet.Start()
		d.logs.Start()
		d.system.Start()
		d.pigo.Start()
	}()

	fmt.Fprintln(os.Stderr, "bot-army: entering event loop...")
	if err := d.app.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "bot-army: event loop error: %v\n", err)
		return err
	}
	fmt.Fprintln(os.Stderr, "bot-army: event loop ended.")

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

// initTabs initializes all tabs.
func (d *Dashboard) initTabs() {
	d.fleet = NewFleetTab()
	d.fleet.Init(d.app, d.cfg)

	d.logs = NewLogsTab()
	d.logs.Init(d.app, d.cfg)

	d.nats = NewNATSTab()
	d.nats.Init(d.app, d.cfg)

	d.system = NewSystemTab()
	d.system.Init(d.app, d.cfg)

	d.pigo = NewPigoTab()
	d.pigo.Init(d.app, d.cfg)

	// Add pages in order
	d.pages.AddPage("fleet", d.fleet.Widget(), true, true)
	d.pages.AddPage("logs", d.logs.Widget(), true, false)
	d.pages.AddPage("nats", d.nats.Widget(), true, false)
	d.pages.AddPage("system", d.system.Widget(), true, false)
	d.pages.AddPage("pigo", d.pigo.Widget(), true, false)

	// Start the fleet tab first
	d.app.SetFocus(d.fleet.Widget())
}

// stopTabs stops all background goroutines in tabs.
func (d *Dashboard) stopTabs() {
	d.fleet.Stop()
	d.logs.Stop()
	d.nats.Stop()
	d.system.Stop()
	d.pigo.Stop()
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
		case '5':
			d.switchTab("pigo", d.pigo.Widget())
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
				d.switchTab("pigo", d.pigo.Widget())
			case "pigo":
				d.switchTab("fleet", d.fleet.Widget())
			}
			return nil

		case tcell.KeyBacktab: // Shift+Tab
			switch d.activeTab {
			case "fleet":
				d.switchTab("pigo", d.pigo.Widget())
			case "logs":
				d.switchTab("fleet", d.fleet.Widget())
			case "nats":
				d.switchTab("logs", d.logs.Widget())
			case "system":
				d.switchTab("nats", d.nats.Widget())
			case "pigo":
				d.switchTab("system", d.system.Widget())
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
	tabs := []string{"fleet", "logs", "nats", "system", "pigo"}
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

// showTemplateGuide displays the Build Your Own Bot guide as an overlay.
func (d *Dashboard) showTemplateGuide() {
	guide := "[yellow]Build Your Own Bot[-]\n\n"
	guide += "A Bot Army bot is an Elixir/OTP GenServer app that subscribes to\n"
	guide += "NATS subjects and responds to messages from other bots and surfaces.\n\n"
	guide += "[cyan]Quick start (one command):[-]\n"
	guide += "  cd ~/code/elixir_bots/bot_template\n"
	guide += "  ./setup_new_bot.sh bot_army_mybot mybot_bot ergon-mybot\n\n"
	guide += "This scaffolds a full project with:\n"
	guide += "  • NATS consumer (subscribe + reply)\n"
	guide += "  • PulsePublisher (health signal every 30 min)\n"
	guide += "  • HTTP client with Mox injection for testing\n"
	guide += "  • Pre-push hook: compile → test → GitHub Release\n"
	guide += "  • Makefile targets: test, format, deploy, logs\n\n"
	guide += "[cyan]Key patterns:[-]\n"
	guide += "  1. Health — publish bot.<service>.pulse every 30 min\n"
	guide += "  2. HTTP — use HTTPClient behaviour + Mox in tests\n"
	guide += "  3. Env gating — @env Mix.env() to skip DB/workers in test\n"
	guide += "  4. Test tagging — @moduletag :handlers, :stores, :skills\n"
	guide += "  5. Skills — lib/.../skills/ modules with validate/1 + execute/2\n"
	guide += "  6. Deploy — bump mix.exs version to trigger GitHub Release\n\n"
	guide += "[cyan]Add to your fleet:[-]\n"
	guide += "  ./bot-army add mybot\n"
	guide += "  docker compose up -d --build\n\n"
	guide += "[cyan]Reference:[-]\n"
	guide += "  bot_template/docs/BEST_PRACTICES.md\n"
	guide += "  bot_template/UPDATES.md\n\n"
	guide += "[dim]Press Esc to close[-]"

	guideView := tview.NewTextView()
	guideView.SetBorder(true).
		SetTitle(" Build Your Own Bot  Esc:close ").
		SetTitleAlign(tview.AlignLeft)
	guideView.SetDynamicColors(true)
	guideView.SetText(guide)

	guideView.SetInputCapture(func(ev *tcell.EventKey) *tcell.EventKey {
		switch ev.Key() {
		case tcell.KeyEscape:
			// Return to previous tab
			d.pages.RemovePage("guide")
			d.app.SetFocus(d.pages)
			return nil
		}
		return ev
	})

	d.pages.AddPage("guide", guideView, true, true)
	d.app.SetFocus(guideView)
}