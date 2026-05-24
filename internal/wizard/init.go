package wizard

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
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

	// Step 1: Select bots
	selectedBots, err := runBotSelector(bots)
	if err != nil {
		return fmt.Errorf("bot selection: %w", err)
	}
	cfg.SelectedBots = selectedBots

	// Step 1.5: Configure host ports
	fmt.Println("\n— Host Ports —")
	fmt.Println("  Container-internal ports stay standard (4222, 5432, etc.)")
	fmt.Println("  Host ports are what you connect to from outside Docker.")
	cfg.Ports.NATS = askWithDefault("NATS host port", DefaultPorts.NATS)
	cfg.Ports.NATSMonitor = askWithDefault("NATS monitor host port", DefaultPorts.NATSMonitor)
	cfg.Ports.Postgres = askWithDefault("PostgreSQL host port", DefaultPorts.Postgres)
	cfg.Ports.Ollama = askWithDefault("Ollama host port", DefaultPorts.Ollama)

	// Step 2: Select LLM providers
	providers, err := runProviderSelector()
	if err != nil {
		return fmt.Errorf("provider selection: %w", err)
	}
	cfg.SelectedProviders = providers

	chain := make([]string, len(providers))
	for i, p := range providers {
		chain[i] = p.Name
	}
	cfg.ProviderChain = strings.Join(chain, ",")

	for _, p := range providers {
		if p.Name == "ollama" && p.CanSelfHost {
			cfg.SelfHostOllama = askYesNo("Run Ollama as a Docker service? (y/n)")
			if cfg.SelfHostOllama {
				cfg.EnvValues["OLLAMA_BASE_URL"] = "http://ollama:11434"
			}
		}
	}

	// Step 3: Collect env vars (providers + bot-specific)
	if err := collectEnvVars(cfg); err != nil {
		return fmt.Errorf("env collection: %w", err)
	}

	// Step 4: Clone repos
	fmt.Println("\nCloning repositories...")
	if err := cloneRepos(cfg); err != nil {
		return fmt.Errorf("clone: %w", err)
	}

	// Step 5: Generate files
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

func runBotSelector(bots []Bot) ([]Bot, error) {
	selected := make(map[int]bool)
	for i, b := range bots {
		if b.IsCore() {
			selected[i] = true
		}
	}

	m := &botSelectorModel{
		bots:     bots,
		selected: selected,
		cursor:   0,
	}

	p := tea.NewProgram(m)
	finalModel, err := p.Run()
	if err != nil {
		return nil, err
	}

	final := finalModel.(*botSelectorModel)
	if final.cancelled {
		return nil, fmt.Errorf("cancelled")
	}

	var result []Bot
	for i, b := range bots {
		if final.selected[i] {
			result = append(result, b)
		}
	}
	return result, nil
}

func runProviderSelector() ([]Provider, error) {
	selected := make(map[int]bool)

	m := &providerSelectorModel{
		providers: Providers,
		selected:  selected,
		cursor:    0,
	}

	p := tea.NewProgram(m)
	finalModel, err := p.Run()
	if err != nil {
		return nil, err
	}

	final := finalModel.(*providerSelectorModel)
	if final.cancelled {
		return nil, fmt.Errorf("cancelled")
	}

	if len(final.selected) == 0 {
		return nil, fmt.Errorf("at least one LLM provider is required")
	}

	var result []Provider
	for i, p := range Providers {
		if final.selected[i] {
			result = append(result, p)
		}
	}
	return result, nil
}

func collectEnvVars(cfg *Config) error {
	// Provider env vars
	for _, p := range cfg.SelectedProviders {
		fmt.Printf("\n— %s —\n", p.Label)
		for _, ev := range p.EnvVars {
			if _, ok := cfg.EnvValues[ev.Key]; ok {
				continue
			}
			cfg.EnvValues[ev.Key] = promptForVar(ev)
		}
	}

	// Bot-specific env vars (from catalog scan)
	for _, bot := range cfg.SelectedBots {
		if len(bot.EnvVars) == 0 {
			continue
		}
		fmt.Printf("\n— %s —\n", bot.DisplayName())
		for _, ev := range bot.EnvVars {
			if _, ok := cfg.EnvValues[ev.Key]; ok {
				continue
			}
			cfg.EnvValues[ev.Key] = promptForVar(ev)
		}
	}
	return nil
}

func promptForVar(ev EnvVar) string {
	if ev.Secret {
		return askSecret(ev.Prompt)
	} else if ev.Default != "" {
		return askWithDefault(ev.Prompt, ev.Default)
	} else if ev.Required {
		return askRequired(ev.Prompt)
	}
	return ev.Default
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

func askWithDefault(prompt, def string) string {
	fmt.Printf("  %s [%s]: ", prompt, def)
	var input string
	fmt.Scanln(&input)
	if input == "" {
		return def
	}
	return input
}

func askRequired(prompt string) string {
	for {
		fmt.Printf("  %s: ", prompt)
		var input string
		fmt.Scanln(&input)
		if input != "" {
			return input
		}
		fmt.Println("  (required)")
	}
}

func askSecret(prompt string) string {
	return askRequired(prompt)
}

func askYesNo(prompt string) bool {
	fmt.Printf("  %s ", prompt)
	var input string
	fmt.Scanln(&input)
	return strings.ToLower(input) == "y" || strings.ToLower(input) == "yes"
}
