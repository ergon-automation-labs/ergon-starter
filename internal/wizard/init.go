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

// CustomBot represents a user-defined bot not in the catalog
type CustomBot struct {
	Name        string            `json:"name"`
	Repo        string            `json:"repo"` // URL or local path
	ReleaseName string            `json:"release_name"`
	EnvVars     map[string]string `json:"env_vars"`
}

// CustomMount represents a custom directory to mount in docker-compose
type CustomMount struct {
	Source      string `json:"source"`      // Host path
	Destination string `json:"destination"` // Container path
}

type Config struct {
	AllBots           []Bot
	SelectedPacks     []Pack
	SelectedBots      []Bot
	SelectedProviders []Provider
	CustomBots        []CustomBot
	CustomMounts      []CustomMount
	ProviderChain     string
	SelfHostOllama    bool
	EnvValues         map[string]string
	InstallDir        string
	GitOrg            string
	Ports             PortMap
	DevMode           bool // True if Development pack selected
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
	DevMode           bool              `json:"dev_mode"`
	CustomBots        []CustomBot       `json:"custom_bots"`
	CustomMounts      []CustomMount     `json:"custom_mounts"`
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
				fmt.Println("✓ Loaded existing configuration")
				fmt.Println()
				// Skip wizard and go straight to setup
				return runSetup(cfg)
			}
		}
		fmt.Println("Running wizard again...")
		fmt.Println()
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
	// Ensure gh is set up for authentication
	fmt.Println("\nSetting up GitHub CLI...")
	if err := ensureGhAuth(); err != nil {
		return fmt.Errorf("gh auth: %w", err)
	}

	// Clone repos
	fmt.Println("\nCloning repositories...")
	if err := cloneRepos(cfg); err != nil {
		return fmt.Errorf("clone: %w", err)
	}

	// Generate files
	fmt.Println()
	fmt.Println("Generating configuration...")
	if err := generateEnvFile(cfg); err != nil {
		return fmt.Errorf("env file: %w", err)
	}
	if err := generateComposeFile(cfg); err != nil {
		return fmt.Errorf("compose file: %w", err)
	}

	fmt.Println()
	fmt.Println("✓ Setup complete!")
	fmt.Println()
	fmt.Println("Starting bot fleet dashboard...")
	fmt.Println("Starting: docker compose up -d --build")
	fmt.Println()

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

	// Clone libraries if in development mode
	if cfg.DevMode {
		libraryRepos := []string{"bot_army_library_runtime", "bot_army_library_core", "bot_army_library_learning"}
		for _, repo := range libraryRepos {
			if err := cloneRepo(reposDir, repo, cfg.GitOrg); err != nil {
				return err
			}
		}
	}

	// Clone selected bots
	for _, bot := range cfg.SelectedBots {
		// Use bot.Remote as the repo name if available, otherwise use bot.Repo
		repoName := bot.Remote
		if repoName == "" {
			repoName = bot.Repo
		}
		if err := cloneRepo(reposDir, repoName, cfg.GitOrg); err != nil {
			return err
		}
	}

	// Clone custom bots
	for _, customBot := range cfg.CustomBots {
		if err := cloneCustomRepo(reposDir, customBot.Repo, customBot.Name); err != nil {
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

	// Try gh first
	fullRepo := fmt.Sprintf("%s/%s", org, repo)
	cmd := exec.Command("gh", "repo", "clone", fullRepo, dest, "--", "--depth", "1")
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err == nil {
		fmt.Println(" ✓")
		return nil
	}

	// Fall back to git
	url := fmt.Sprintf("https://github.com/%s/%s.git", org, repo)
	cmd = exec.Command("git", "clone", "--depth", "1", url, dest)
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Println(" ✗")
		return fmt.Errorf("clone %s: %w", repo, err)
	}
	fmt.Println(" ✓")
	return nil
}

// cloneCustomRepo clones a custom bot repository (URL or local path)
func cloneCustomRepo(reposDir, repoURL, botName string) error {
	dest := filepath.Join(reposDir, botName)

	// Check if already exists
	if _, err := os.Stat(dest); err == nil {
		fmt.Printf("  ✓ %s (exists)\n", botName)
		return nil
	}

	fmt.Printf("  ⏳ %s...", botName)

	// Check if it's a local path
	if _, err := os.Stat(repoURL); err == nil {
		// Local path - copy instead of clone
		cmd := exec.Command("cp", "-r", repoURL, dest)
		if err := cmd.Run(); err != nil {
			fmt.Println(" ✗")
			return fmt.Errorf("copy %s: %w", botName, err)
		}
		fmt.Println(" ✓")
		return nil
	}

	// Try git clone (handles both https and ssh URLs)
	cmd := exec.Command("git", "clone", "--depth", "1", repoURL, dest)
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Println(" ✗")
		return fmt.Errorf("clone %s: %w", botName, err)
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
		DevMode:           cfg.DevMode,
		CustomBots:        cfg.CustomBots,
		CustomMounts:      cfg.CustomMounts,
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
	cfg.DevMode = cf.DevMode
	cfg.CustomBots = cf.CustomBots
	cfg.CustomMounts = cf.CustomMounts

	return nil
}

// ensureGhAuth ensures gh CLI is installed and authenticated.
func ensureGhAuth() error {
	// Check if gh is installed
	if err := exec.Command("which", "gh").Run(); err != nil {
		fmt.Println("  Installing GitHub CLI...")
		if err := installGh(); err != nil {
			fmt.Println("  ⚠ Could not install gh. Using git with credentials instead.")
			fmt.Println()
			return nil // Don't fail, git will prompt for credentials
		}
		fmt.Println("  ✓ GitHub CLI installed")
	}

	// Check if gh is authenticated
	statusCmd := exec.Command("gh", "auth", "status")
	statusCmd.Stdout = nil // suppress output
	statusCmd.Stderr = nil
	if err := statusCmd.Run(); err != nil {
		// Not authenticated, need to auth
		fmt.Println("  GitHub authentication required")
		fmt.Println()
		fmt.Println("  Running: gh auth login")
		authCmd := exec.Command("gh", "auth", "login")
		authCmd.Stdin = os.Stdin
		authCmd.Stdout = os.Stdout
		authCmd.Stderr = os.Stderr
		if err := authCmd.Run(); err != nil {
			fmt.Println("  ⚠ gh auth failed. Using git with credentials instead.")
			fmt.Println()
			return nil // Don't fail, git will prompt for credentials
		}
		fmt.Println()
	}

	fmt.Println("  ✓ GitHub authenticated")
	return nil
}

// installGh attempts to install gh from GitHub releases.
func installGh() error {
	// Try apk first (might work on some Alpine configs)
	if err := exec.Command("apk", "add", "--no-cache", "gh").Run(); err == nil {
		return nil
	}

	// Fall back: download binary from GitHub releases for Alpine/Linux
	fmt.Println("    Downloading gh binary...")
	tmpDir := "/tmp"
	tarPath := filepath.Join(tmpDir, "gh.tar.gz")

	// Download (adjust architecture if needed - using x86_64 for common case)
	downloadCmd := exec.Command("wget", "-q", "-O", tarPath,
		"https://github.com/cli/cli/releases/download/v2.50.0/gh_2.50.0_linux_amd64.tar.gz")
	if err := downloadCmd.Run(); err != nil {
		return fmt.Errorf("download failed: %w", err)
	}

	// Extract
	extractCmd := exec.Command("tar", "-xzf", tarPath, "-C", tmpDir)
	if err := extractCmd.Run(); err != nil {
		return fmt.Errorf("extract failed: %w", err)
	}

	// Copy to PATH
	cpCmd := exec.Command("cp", filepath.Join(tmpDir, "gh_2.50.0_linux_amd64", "bin", "gh"), "/usr/local/bin/gh")
	if err := cpCmd.Run(); err != nil {
		return fmt.Errorf("install failed: %w", err)
	}

	// Cleanup
	_ = exec.Command("rm", "-rf", tarPath, filepath.Join(tmpDir, "gh_2.50.0_linux_amd64")).Run()

	return nil
}
