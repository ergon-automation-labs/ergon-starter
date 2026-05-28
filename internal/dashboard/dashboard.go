package dashboard

import (
	"fmt"
	"os"
	"strings"

	"github.com/gdamore/tcell/v2"
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
	app         *tview.Application
	cfg         *DashboardConfig
	header      *tview.TextView
	statusBar   *tview.TextView
	contentArea *tview.TextView
	root        tview.Primitive
}

// NewDashboard creates a new dashboard.
func NewDashboard(cfg *DashboardConfig) *Dashboard {
	d := &Dashboard{
		cfg: cfg,
	}

	// Create views BEFORE app exists (like GTD does)
	d.header = tview.NewTextView()
	d.header.SetDynamicColors(true)
	d.header.SetText("🤖 Bot Army Dashboard  [q:quit]")

	d.contentArea = tview.NewTextView()
	d.contentArea.SetDynamicColors(true)
	d.contentArea.SetBorder(true)
	d.contentArea.SetTitle(" Fleet ")

	d.statusBar = tview.NewTextView()
	d.statusBar.SetDynamicColors(true)
	d.statusBar.SetText("Loading...")

	// Build layout NOW, before app exists
	d.buildLayout()

	return d
}

// buildLayout builds the tview hierarchy
func (d *Dashboard) buildLayout() {
	flex := tview.NewFlex().SetDirection(tview.FlexRow).
		AddItem(d.header, 1, 0, false).
		AddItem(d.contentArea, 0, 1, true).
		AddItem(d.statusBar, 1, 0, false)

	d.root = flex
	d.updateContent()
}

// updateContent refreshes the main content area
func (d *Dashboard) updateContent() {
	containers, err := DockerPS()
	if err != nil {
		d.contentArea.SetText("[red]Docker not running[-]")
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

	text += "Services:\n"
	text += fmt.Sprintf("  NATS:     %s\n", statusIcon(natsRunning))
	text += fmt.Sprintf("  Postgres: %s\n\n", statusIcon(postgresRunning))

	text += "Bots:\n"
	for _, c := range containers {
		if strings.Contains(c.Names, "nats") || strings.Contains(c.Names, "postgres") {
			continue
		}
		running := strings.Contains(c.State, "running")
		text += fmt.Sprintf("  %s %s (%s)\n", statusIcon(running), c.Names, c.State)
	}

	d.contentArea.SetText(text)
}

func statusIcon(running bool) string {
	if running {
		return "✓"
	}
	return "✗"
}

// SetApp sets the tview application (called from main after New())
func (d *Dashboard) SetApp(app *tview.Application) {
	d.app = app
}

// OnActivate is called when the app starts
func (d *Dashboard) OnActivate() {
	d.statusBar.SetText("Ready. Press q to quit or Tab for menu.")
	if d.app != nil {
		d.app.SetFocus(d.contentArea)
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
	case 'r':
		d.updateContent()
		if d.app != nil {
			d.app.QueueUpdateDraw(func() {
				d.statusBar.SetText("Refreshed")
			})
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
