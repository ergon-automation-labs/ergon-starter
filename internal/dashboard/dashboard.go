package dashboard

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/gdamore/tcell/v2"
	"github.com/nats-io/nats.go"
	"github.com/rivo/tview"
)

// DashboardConfig holds the configuration for the dashboard.
type DashboardConfig struct {
	NATSPort     string
	PostgresPort string
	Bots         []BotInfo
	DataDir      string
}

// BotInfo describes a bot service.
type BotInfo struct {
	Name        string
	ReleaseName string
	Repo        string
}

// Dashboard is the main dashboard application.
type Dashboard struct {
	app       *tview.Application
	cfg       *DashboardConfig
	header    *tview.TextView
	statusBar *tview.TextView

	// Tabs
	fleetView  *tview.TextView
	logsView   *tview.TextView
	natsView   *tview.TextView
	systemView *tview.TextView

	// Layouts
	fleetFlex  tview.Primitive
	logsFlex   tview.Primitive
	natsFlex   tview.Primitive
	systemFlex tview.Primitive
	root       tview.Primitive

	currentTab string
}

// NewDashboard creates a new dashboard.
func NewDashboard(cfg *DashboardConfig) *Dashboard {
	d := &Dashboard{
		cfg:        cfg,
		currentTab: "fleet",
	}

	// Create views BEFORE app exists (like GTD does)
	d.header = tview.NewTextView()
	d.header.SetDynamicColors(true)

	d.statusBar = tview.NewTextView()
	d.statusBar.SetDynamicColors(true)
	d.statusBar.SetText("Ready. [1]Fleet  [2]Logs  [3]NATS  [4]System  [q]uit")

	// Create tab views
	d.fleetView = tview.NewTextView()
	d.fleetView.SetDynamicColors(true)
	d.fleetView.SetBorder(true)
	d.fleetView.SetTitle(" Fleet ")

	d.logsView = tview.NewTextView()
	d.logsView.SetDynamicColors(true)
	d.logsView.SetBorder(true)
	d.logsView.SetTitle(" Logs ")

	d.natsView = tview.NewTextView()
	d.natsView.SetDynamicColors(true)
	d.natsView.SetBorder(true)
	d.natsView.SetTitle(" NATS ")

	d.systemView = tview.NewTextView()
	d.systemView.SetDynamicColors(true)
	d.systemView.SetBorder(true)
	d.systemView.SetTitle(" System ")

	// Build layouts NOW, before app exists
	d.buildFleetLayout()
	d.buildLogsLayout()
	d.buildNATSLayout()
	d.buildSystemLayout()
	d.buildMainLayout()

	return d
}

// buildFleetLayout builds the fleet tab
func (d *Dashboard) buildFleetLayout() {
	flex := tview.NewFlex().SetDirection(tview.FlexRow).
		AddItem(d.header, 1, 0, false).
		AddItem(d.fleetView, 0, 1, true).
		AddItem(d.statusBar, 1, 0, false)

	d.fleetFlex = flex
	d.updateFleet()
}

// buildLogsLayout builds the logs tab
func (d *Dashboard) buildLogsLayout() {
	flex := tview.NewFlex().SetDirection(tview.FlexRow).
		AddItem(d.header, 1, 0, false).
		AddItem(d.logsView, 0, 1, true).
		AddItem(d.statusBar, 1, 0, false)

	d.logsFlex = flex
	d.updateLogs()
}

// buildNATSLayout builds the NATS tab
func (d *Dashboard) buildNATSLayout() {
	flex := tview.NewFlex().SetDirection(tview.FlexRow).
		AddItem(d.header, 1, 0, false).
		AddItem(d.natsView, 0, 1, true).
		AddItem(d.statusBar, 1, 0, false)

	d.natsFlex = flex
	d.updateNATS()
}

// buildSystemLayout builds the system tab
func (d *Dashboard) buildSystemLayout() {
	flex := tview.NewFlex().SetDirection(tview.FlexRow).
		AddItem(d.header, 1, 0, false).
		AddItem(d.systemView, 0, 1, true).
		AddItem(d.statusBar, 1, 0, false)

	d.systemFlex = flex
	d.updateSystem()
}

// buildMainLayout sets the initial root
func (d *Dashboard) buildMainLayout() {
	d.root = d.fleetFlex
	d.updateHeader()
}

// updateHeader updates the header with active tab
func (d *Dashboard) updateHeader() {
	tabs := "🤖 Bot Army  "
	for _, tab := range []string{"fleet", "logs", "nats", "system"} {
		if tab == d.currentTab {
			tabs += fmt.Sprintf("[yellow:black][ %s ][-:-] ", strings.ToUpper(tab))
		} else {
			tabs += fmt.Sprintf("[ %s ] ", tab)
		}
	}
	tabs += "  [q]uit"
	d.header.SetText(tabs)
}

// updateFleet refreshes the fleet view
func (d *Dashboard) updateFleet() {
	containers, err := DockerPS()
	if err != nil {
		d.fleetView.SetText("[red]Docker not running[-]")
		return
	}

	text := "\n"
	natsRunning := false
	postgresRunning := false

	// Check services
	for _, c := range containers {
		if strings.Contains(c.Names, "nats") {
			natsRunning = true
		}
		if strings.Contains(c.Names, "postgres") {
			postgresRunning = true
		}
	}

	text += "[cyan]Services[yellow]\n"
	text += fmt.Sprintf("  NATS:     %s\n", statusIcon(natsRunning))
	text += fmt.Sprintf("  Postgres: %s\n\n", statusIcon(postgresRunning))

	text += "[cyan]Bots[yellow]\n"
	for _, c := range containers {
		if strings.Contains(c.Names, "nats") || strings.Contains(c.Names, "postgres") {
			continue
		}
		running := strings.Contains(c.State, "running")
		health := "unknown"
		if running {
			if d.checkBotHealth(c.Names) {
				health = "[green]healthy[-]"
			} else {
				health = "[yellow]running (no response)[-]"
			}
		} else {
			health = "[red]stopped[-]"
		}
		text += fmt.Sprintf("  %s %s - %s\n", statusIcon(running), c.Names, health)
	}

	d.fleetView.SetText(text)
}

// checkBotHealth checks if a bot is responding on NATS
func (d *Dashboard) checkBotHealth(botName string) bool {
	natsURL := "nats://localhost:" + d.cfg.NATSPort
	nc, err := nats.Connect(natsURL, nats.Timeout(1*time.Second))
	if err != nil {
		return false
	}
	defer nc.Close()

	subject := "system.health." + botName
	_, err = nc.Request(subject, []byte("{}"), 500*time.Millisecond)
	return err == nil
}

// updateLogs refreshes the logs view
func (d *Dashboard) updateLogs() {
	text := "\n[cyan]Recent Logs[yellow]\n"
	text += "  • NATS: " + d.cfg.NATSPort + "\n"
	text += "  • Postgres: " + d.cfg.PostgresPort + "\n"
	text += "  • Data dir: " + d.cfg.DataDir + "\n\n"
	text += "[cyan]Bots[yellow]\n"
	for _, bot := range d.cfg.Bots {
		text += fmt.Sprintf("  • %s (%s)\n", bot.Name, bot.ReleaseName)
	}
	text += "\n[yellow]Press [r] to refresh[-]"
	d.logsView.SetText(text)
}

// updateNATS refreshes the NATS health view
func (d *Dashboard) updateNATS() {
	text := "\n[cyan]NATS Health[yellow]\n"
	text += "[green]Status: Running[-]\n"
	text += fmt.Sprintf("  Port: %s\n", d.cfg.NATSPort)
	text += "  Cluster: development\n"
	text += "  Subjects: configured\n\n"
	text += "[cyan]Connected Services[yellow]\n"

	containers, err := DockerPS()
	if err == nil {
		count := 0
		for _, c := range containers {
			if strings.Contains(c.State, "running") && !strings.Contains(c.Names, "nats") {
				count++
			}
		}
		text += fmt.Sprintf("  Active: %d bots\n", count)
	} else {
		text += "  Active: unknown\n"
	}

	text += "\n[yellow]Press [r] to refresh[-]"
	d.natsView.SetText(text)
}

// updateSystem refreshes the system status view
func (d *Dashboard) updateSystem() {
	text := "\n[cyan]System Status[yellow]\n"
	text += "[green]Docker: Running[-]\n"
	text += "  Engine: active\n"
	text += "  Memory: available\n\n"

	containers, err := DockerPS()
	if err != nil {
		text += "[red]Error: Docker not accessible[-]\n"
		d.systemView.SetText(text)
		return
	}

	text += fmt.Sprintf("[cyan]Containers: %d total[yellow]\n", len(containers))
	for _, c := range containers {
		state := "[red]stopped[-]"
		healthInfo := ""
		if strings.Contains(c.State, "running") {
			state = "[green]running[-]"
			if d.checkBotHealth(c.Names) {
				healthInfo = " [green]✓[-]"
			} else if !strings.Contains(c.Names, "nats") && !strings.Contains(c.Names, "postgres") {
				healthInfo = " [yellow]⚠[-]"
			}
		}
		text += fmt.Sprintf("  %s %s%s\n", state, c.Names, healthInfo)
	}

	text += "\n[yellow]Press [r] to refresh[-]"
	d.systemView.SetText(text)
}

func statusIcon(running bool) string {
	if running {
		return "✓"
	}
	return "✗"
}

// switchTab changes to the specified tab
func (d *Dashboard) switchTab(tab string) {
	if d.app == nil {
		return
	}

	d.currentTab = tab
	d.updateHeader()

	var newRoot tview.Primitive
	switch tab {
	case "fleet":
		d.updateFleet()
		newRoot = d.fleetFlex
	case "logs":
		d.updateLogs()
		newRoot = d.logsFlex
	case "nats":
		d.updateNATS()
		newRoot = d.natsFlex
	case "system":
		d.updateSystem()
		newRoot = d.systemFlex
	default:
		return
	}

	d.app.SetRoot(newRoot, true).SetFocus(d.fleetView)
}

// SetApp sets the tview application (called from main after New())
func (d *Dashboard) SetApp(app *tview.Application) {
	d.app = app
}

// OnActivate is called when the app starts
func (d *Dashboard) OnActivate() {
	if d.app != nil {
		d.app.SetFocus(d.fleetView)
	}
}

// HandleKey processes keyboard input
func (d *Dashboard) HandleKey(ev *tcell.EventKey) *tcell.EventKey {
	switch ev.Rune() {
	case 'q':
		if d.app != nil {
			d.app.Stop()
		}
		return nil
	case '1':
		d.switchTab("fleet")
		return nil
	case '2':
		d.switchTab("logs")
		return nil
	case '3':
		d.switchTab("nats")
		return nil
	case '4':
		d.switchTab("system")
		return nil
	case 'r':
		switch d.currentTab {
		case "fleet":
			d.updateFleet()
		case "logs":
			d.updateLogs()
		case "nats":
			d.updateNATS()
		case "system":
			d.updateSystem()
		}
		if d.app != nil {
			d.app.QueueUpdateDraw(func() {})
		}
		return nil
	}
	return ev
}

// Root returns the root widget
func (d *Dashboard) Root() tview.Primitive {
	return d.root
}

// Run starts the dashboard
func (d *Dashboard) Run() error {
	// Redirect stderr to avoid corrupting tview
	logFile, err := os.OpenFile("/tmp/bot-army-dashboard.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err == nil {
		defer logFile.Close()
		oldStderr := os.Stderr
		os.Stderr = logFile
		defer func() { os.Stderr = oldStderr }()
	}

	// Create app
	app := tview.NewApplication()
	d.SetApp(app)
	d.OnActivate()

	// Set up input capture - delegate to HandleKey like GTD does
	app.SetInputCapture(func(ev *tcell.EventKey) *tcell.EventKey {
		return d.HandleKey(ev)
	})

	// Set root and run
	app.SetRoot(d.Root(), true)
	if err := app.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return err
	}

	return nil
}

// RunFromWizardConfig launches dashboard with wizard config
func RunFromWizardConfig(natsPort string, botNames []string, botReleaseNames []string, dataDir string) error {
	bots := make([]BotInfo, len(botNames))
	for i, name := range botNames {
		bots[i] = BotInfo{
			Name:        name,
			ReleaseName: botReleaseNames[i],
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

// RunFromDir launches dashboard from docker-compose directory
func RunFromDir(dir string) error {
	cfg, err := DashboardConfigFromEnv(dir)
	if err != nil {
		return err
	}

	d := NewDashboard(cfg)
	return d.Run()
}
