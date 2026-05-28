package dashboard

import (
	"fmt"
	"strings"
)

func logDebug(msg string) {
	// No-op for CLI version
}

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

// Dashboard shows bot status via CLI
type Dashboard struct {
	cfg *DashboardConfig
}

// NewDashboard creates a new dashboard.
func NewDashboard(cfg *DashboardConfig) *Dashboard {
	return &Dashboard{cfg: cfg}
}

// Run shows a simple CLI status display of running bots and services
func (d *Dashboard) Run() error {
	// Get Docker containers
	containers, err := DockerPS()
	if err != nil {
		fmt.Printf("❌ Docker not running: %v\n", err)
		return err
	}

	if len(containers) == 0 {
		fmt.Println("No containers running. Start with: docker compose up -d")
		return nil
	}

	// Print header
	fmt.Println("\n🤖 Bot Army Status")
	fmt.Println(strings.Repeat("─", 60))

	// Group containers by type
	natsRunning := false
	postgresRunning := false
	bots := []DockerContainer{}

	for _, c := range containers {
		switch {
		case strings.Contains(c.Names, "nats"):
			natsRunning = true
		case strings.Contains(c.Names, "postgres"):
			postgresRunning = true
		default:
			bots = append(bots, c)
		}
	}

	// Print services
	fmt.Println("\n📋 Services")
	fmt.Printf("  NATS:     %s\n", statusIcon(natsRunning))
	fmt.Printf("  Postgres: %s\n", statusIcon(postgresRunning))

	// Print bots
	fmt.Println("\n🤖 Bots")
	for _, bot := range bots {
		running := strings.Contains(bot.State, "running")
		fmt.Printf("  %s %s (%s)\n", statusIcon(running), bot.Names, bot.State)
	}

	// Print info
	fmt.Println("\n📚 Commands")
	fmt.Println("  docker compose logs <service>     - View logs")
	fmt.Println("  docker compose restart <service>  - Restart service")
	fmt.Println("  docker compose down               - Stop all services")
	fmt.Println("\n")

	return nil
}

func statusIcon(running bool) string {
	if running {
		return "✓"
	}
	return "✗"
}

// RunFromWizardConfig launches the dashboard with a wizard Config.
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
