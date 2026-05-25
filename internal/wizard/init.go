package wizard

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/abby/bot-army-starter/internal/dashboard"
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
	SelectedPacks     []Pack
	SelectedBots      []Bot
	SelectedProviders []Provider
	ProviderChain     string
	SelfHostOllama    bool
	EnvValues         map[string]string
	InstallDir        string
	GitOrg            string
	Ports             PortMap
}

// ConfigFile is serializable version of Config for persistence.
type ConfigFile struct {
	SelectedBotNames  []string          `json:"selected_bots"`
	SelectedPackNames []string          `json:"selected_packs"`
	ProviderNames     []string          `json:"providers"`
	ProviderChain     string            `json:"provider_chain"`
	SelfHostOllama    bool              `json:"self_host_ollama"`
	EnvValues         map[string]string `json:"env_values"`
	Ports             PortMap           `json:"ports"`
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

	// Check for existing config
	configPath := filepath.Join(cfg.InstallDir, ".bot-army.json")
	if _, err := os.Stat(configPath); err == nil {
		// Config exists, offer to reuse it
		fmt.Print("Found existing configuration. Reuse it? (y/n): ")
		var response string
		fmt.Scanln(&response)
		if strings.ToLower(response) == "y" || strings.ToLower(response) == "yes" {
			if err := loadConfigInto(cfg, configPath); err == nil {
				fmt.Println("✓ Loaded existing configuration\n")
				// Skip wizard and go straight to setup
				return runSetup(cfg)
			}
		}
		fmt.Println("Running wizard again...\n")
	}

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

	// Save config for future reuse
	if err := saveConfig(cfg); err != nil {
		fmt.Printf("Warning: could not save config: %v\n", err)
	}

	return runSetup(cfg)
}

// runSetup clones repos, generates config files, and starts the dashboard.
func runSetup(cfg *Config) error {
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
	fmt.Println("\nStarting bot fleet dashboard...")
	fmt.Println("Starting: docker compose up -d --build\n")

	// Start Docker containers
	startCmd := exec.Command("docker", "compose", "up", "-d", "--build")
	startCmd.Stdout = os.Stdout
	startCmd.Stderr = os.Stderr
	if err := startCmd.Run(); err != nil {
		// Don't fail if docker compose fails — dashboard can still show useful state
		fmt.Printf("Warning: docker compose up failed: %v\n\n", err)
	}

	// Launch dashboard (this will block until user quits)
	botNames := make([]string, len(cfg.SelectedBots))
	botReleaseNames := make([]string, len(cfg.SelectedBots))
	for i, bot := range cfg.SelectedBots {
		botNames[i] = bot.Name
		botReleaseNames[i] = bot.ReleaseName
	}

	return dashboard.RunFromWizardConfig(cfg.Ports.NATS, botNames, botReleaseNames, "./data/logs/")
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

// saveConfig saves the wizard configuration to .bot-army.json.
func saveConfig(cfg *Config) error {
	// Build bot name list
	botNames := make([]string, len(cfg.SelectedBots))
	for i, b := range cfg.SelectedBots {
		botNames[i] = b.Name
	}

	// Build pack name list
	packNames := make([]string, len(cfg.SelectedPacks))
	for i, p := range cfg.SelectedPacks {
		packNames[i] = p.Name
	}

	// Build provider name list
	providerNames := make([]string, len(cfg.SelectedProviders))
	for i, p := range cfg.SelectedProviders {
		providerNames[i] = p.Name
	}

	cf := &ConfigFile{
		SelectedBotNames:  botNames,
		SelectedPackNames: packNames,
		ProviderNames:     providerNames,
		ProviderChain:     cfg.ProviderChain,
		SelfHostOllama:    cfg.SelfHostOllama,
		EnvValues:         cfg.EnvValues,
		Ports:             cfg.Ports,
	}

	data, err := json.MarshalIndent(cf, "", "  ")
	if err != nil {
		return err
	}

	configPath := filepath.Join(cfg.InstallDir, ".bot-army.json")
	return os.WriteFile(configPath, data, 0o600)
}

// loadConfigInto populates a Config from a saved .bot-army.json file.
func loadConfigInto(cfg *Config, configPath string) error {
	data, err := os.ReadFile(configPath)
	if err != nil {
		return err
	}

	var cf ConfigFile
	if err := json.Unmarshal(data, &cf); err != nil {
		return err
	}

	// Restore selected bots by name
	botMap := make(map[string]*Bot)
	for i := range cfg.AllBots {
		botMap[cfg.AllBots[i].Name] = &cfg.AllBots[i]
	}
	for _, name := range cf.SelectedBotNames {
		if b, ok := botMap[name]; ok {
			cfg.SelectedBots = append(cfg.SelectedBots, *b)
		}
	}

	// Restore selected packs by name (load them first)
	packs, err := LoadPacks()
	if err == nil {
		packMap := make(map[string]*Pack)
		for i := range packs {
			packMap[packs[i].Name] = &packs[i]
		}
		for _, name := range cf.SelectedPackNames {
			if p, ok := packMap[name]; ok {
				cfg.SelectedPacks = append(cfg.SelectedPacks, *p)
			}
		}
	}

	// Restore selected providers by name
	providerMap := make(map[string]*Provider)
	for i := range Providers {
		providerMap[Providers[i].Name] = &Providers[i]
	}
	for _, name := range cf.ProviderNames {
		if p, ok := providerMap[name]; ok {
			cfg.SelectedProviders = append(cfg.SelectedProviders, *p)
		}
	}

	// Restore other fields
	cfg.ProviderChain = cf.ProviderChain
	cfg.SelfHostOllama = cf.SelfHostOllama
	cfg.EnvValues = cf.EnvValues
	cfg.Ports = cf.Ports

	return nil
}

