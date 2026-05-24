package wizard

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// PortMap holds host-facing ports. Container-internal ports stay standard.
type PortMap struct {
	NATS         string // host:container 4222
	NATSMonitor  string // host:container 8222
	Postgres     string // host:container 5432
	Ollama       string // host:container 11434
}

var DefaultPorts = PortMap{
	NATS:        "54222",
	NATSMonitor: "58222",
	Postgres:    "55432",
	Ollama:      "51434",
}

type Config struct {
	AllBots           []Bot
	SelectedBots      []Bot
	SelectedProviders []Provider
	ProviderChain     string
	SelfHostOllama    bool
	EnvValues         map[string]string
	InstallDir        string
	GitOrg            string
	Ports             PortMap
}

func RunInit() error {
	cfg := &Config{
		EnvValues:  make(map[string]string),
		InstallDir: ".",
		GitOrg:     "ergon-automation-labs",
		Ports:      DefaultPorts,
	}

	// Load bot catalog
	bots, err := LoadBots()
	if err != nil {
		return err
	}
	cfg.AllBots = bots

	fmt.Printf("Loaded %d bots from catalog\n\n", len(bots))

	// Run the tview wizard
	wizard := NewWizardTUI(cfg)
	if err := wizard.Run(); err != nil {
		return fmt.Errorf("wizard: %w", err)
	}

	// Build provider chain string
	chain := make([]string, len(cfg.SelectedProviders))
	for i, p := range cfg.SelectedProviders {
		chain[i] = p.Name
	}
	cfg.ProviderChain = strings.Join(chain, ",")

	// Check if Ollama should self-host
	for _, p := range cfg.SelectedProviders {
		if p.Name == "ollama" && p.CanSelfHost {
			// Default to no self-host; user would have set env var if desired
			// (could add a step in wizard if we want to prompt)
			cfg.SelfHostOllama = cfg.EnvValues["OLLAMA_SELF_HOST"] != ""
			if cfg.SelfHostOllama {
				cfg.EnvValues["OLLAMA_BASE_URL"] = "http://ollama:11434"
			}
		}
	}

	// Clone repos
	fmt.Println("\nCloning repositories...")
	if err := cloneRepos(cfg); err != nil {
		return fmt.Errorf("clone: %w", err)
	}

	// Generate files
	fmt.Println("\nGenerating configuration...")
	if err := generateEnvFile(cfg); err != nil {
		return fmt.Errorf("env file: %w", err)
	}
	if err := generateComposeFile(cfg); err != nil {
		return fmt.Errorf("compose file: %w", err)
	}

	fmt.Println("\n✓ Setup complete!")
	fmt.Println("\nNext steps:")
	fmt.Println("  docker compose up -d --build")
	fmt.Println("  docker compose logs -f")
	return nil
}

func cloneRepos(cfg *Config) error {
	reposDir := filepath.Join(cfg.InstallDir, "repos")
	os.MkdirAll(reposDir, 0o755)

	coreRepos := []string{"bot_army_runtime", "bot_army_core"}
	for _, repo := range coreRepos {
		if err := cloneRepo(reposDir, repo, cfg.GitOrg); err != nil {
			return err
		}
	}

	for _, bot := range cfg.SelectedBots {
		remote := bot.Remote
		if remote == "" {
			remote = bot.Repo
		}
		if err := cloneRepo(reposDir, bot.Repo, cfg.GitOrg); err != nil {
			return err
		}
	}
	return nil
}

func cloneRepo(reposDir, repo, org string) error {
	dest := filepath.Join(reposDir, repo)
	if _, err := os.Stat(dest); err == nil {
		fmt.Printf("  ✓ %s (exists)\n", repo)
		return nil
	}

	fmt.Printf("  ⏳ %s...", repo)
	url := fmt.Sprintf("https://github.com/%s/%s.git", org, repo)
	cmd := exec.Command("git", "clone", "--depth", "1", url, dest)
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Println(" ✗")
		return fmt.Errorf("clone %s: %w", repo, err)
	}
	fmt.Println(" ✓")
	return nil
}

