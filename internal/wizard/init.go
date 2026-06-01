package wizard

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"

	"github.com/abby/bot-army-starter/internal/dashboard"
)

// PortMap holds host-facing ports. Container-internal ports stay standard.
type PortMap struct {
	NATS           string // host:container 4222
	NATSMonitor    string // host:container 8222
	Postgres       string // host:container 5432
	Ollama         string // host:container 11434
	MCP            string // host:container 39900
	Registry       string // host:container 32000
	GitHubWebhook  string // host:container 39904
}

var DefaultPorts = PortMap{
	NATS:          "54222",
	NATSMonitor:   "58222",
	Postgres:      "55432",
	Ollama:        "51434",
	MCP:           "39900",
	Registry:      "32000",
	GitHubWebhook: "39904",
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
	GitHubToken       string
	GitHubWebhookSecret string
	TerminalContext   bool // Install bot-army-shell (terminal context helper)
}

// ConfigFile is serializable version of Config for persistence.
type ConfigFile struct {
	SelectedBotNames        []string          `json:"selected_bots"`
	SelectedPackNames       []string          `json:"selected_packs"`
	ProviderNames           []string          `json:"providers"`
	ProviderChain           string            `json:"provider_chain"`
	SelfHostOllama          bool              `json:"self_host_ollama"`
	EnvValues               map[string]string `json:"env_values"`
	Ports                   PortMap           `json:"ports"`
	DevMode                 bool              `json:"dev_mode"`
	CustomBots              []CustomBot       `json:"custom_bots"`
	CustomMounts            []CustomMount     `json:"custom_mounts"`
	GitHubToken             string            `json:"github_token,omitempty"`
	GitHubWebhookSecret     string            `json:"github_webhook_secret,omitempty"`
	TerminalContext         bool              `json:"terminal_context,omitempty"`
}

func RunInit() error {
	return RunInitWithCustomBots("")
}

func RunInitWithCustomBots(customBotsFile string) error {
	// Check for required packages
	checkRequiredPackages()

	cfg := &Config{
		EnvValues:  make(map[string]string),
		InstallDir: ".",
		GitOrg:     "ergon-automation-labs",
		Ports:      DefaultPorts,
	}

	// Load custom bots if provided
	if customBotsFile != "" {
		if err := loadCustomBots(cfg, customBotsFile); err != nil {
			return fmt.Errorf("loading custom bots: %w", err)
		}
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

	// Install terminal context helper if enabled
	if cfg.TerminalContext {
		fmt.Println()
		fmt.Println("Installing terminal context helper...")
		if err := installTerminalContext(); err != nil {
			fmt.Printf("Warning: could not install terminal context: %v\n", err)
		} else {
			fmt.Println("✓ Terminal context helper installed")
			fmt.Println()
			fmt.Println("Add to ~/.zshrc:")
			fmt.Println("  source ~/.config/bot-army-shell/bot-army-context.zsh")
			fmt.Println("  RPROMPT+='$$(bot_army_context_prompt)'")
			fmt.Println()
			fmt.Println("For Ghostty, add to ~/.config/ghostty/config:")
			fmt.Println("  title-command = ~/.config/bot-army-shell/bot-army-context-title")
		}
	}

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
	// In pack mode, only show pack containers (not individual bots within packs).
	// In per-bot mode, show individual bot containers.
	var dashboardNames []string
	var dashboardReleaseNames []string
	if len(cfg.SelectedPacks) > 0 {
		for _, pack := range cfg.SelectedPacks {
			if pack.Name == "development" {
				continue
			}
			dashboardNames = append(dashboardNames, pack.Name)
			dashboardReleaseNames = append(dashboardReleaseNames, pack.ReleaseName)
		}
	} else {
		for _, bot := range cfg.SelectedBots {
			dashboardNames = append(dashboardNames, bot.Name)
			dashboardReleaseNames = append(dashboardReleaseNames, bot.ReleaseName)
		}
	}
	for _, customBot := range cfg.CustomBots {
		dashboardNames = append(dashboardNames, customBot.Name)
		dashboardReleaseNames = append(dashboardReleaseNames, customBot.ReleaseName)
	}

	return dashboard.RunFromWizardConfig(cfg.Ports.NATS, dashboardNames, dashboardReleaseNames, "./data/logs/")
}

type cloneTask struct {
	remote   string
	destName string
	org      string
	isCustom bool
}

func cloneRepos(cfg *Config) error {
	reposDir := filepath.Join(cfg.InstallDir, "repos")
	os.MkdirAll(reposDir, 0o755)

	// Collect all repos to clone
	var tasks []cloneTask

	// Libraries if in development mode
	if cfg.DevMode {
		libraryRemotes := map[string]string{
			"bot_army_library_runtime": "ergon-library-runtime",
			"bot_army_library_core":    "ergon-library-core",
			"bot_army_library_learning": "ergon-library-learning",
		}
		for dest, remote := range libraryRemotes {
			tasks = append(tasks, cloneTask{remote: remote, destName: dest, org: cfg.GitOrg})
		}
	}

	// Pack repos
	packRepoMap := map[string]string{
		"core":              "ergon-pack-core",
		"areas":             "ergon-pack-areas",
		"learning_deepdive": "ergon-pack-learning-deepdive",
		"social_media":      "ergon-pack-social-media",
		"research":          "ergon-pack-research",
	}
	for _, pack := range cfg.SelectedPacks {
		if remote, ok := packRepoMap[pack.Name]; ok {
			tasks = append(tasks, cloneTask{remote: remote, destName: "ergon-pack-" + pack.Name, org: cfg.GitOrg})
		}
	}

	// Selected bots
	for _, bot := range cfg.SelectedBots {
		remote := bot.Remote
		if remote == "" {
			remote = bot.Repo
		}
		tasks = append(tasks, cloneTask{remote: remote, destName: bot.Repo, org: cfg.GitOrg})
	}

	// Custom bots
	for _, customBot := range cfg.CustomBots {
		tasks = append(tasks, cloneTask{remote: customBot.Repo, destName: customBot.Name, org: cfg.GitOrg, isCustom: true})
	}

	// Clone all repos concurrently (up to 6 parallel)
	return cloneParallel(reposDir, tasks, 6)
}

func cloneParallel(reposDir string, tasks []cloneTask, maxConcurrent int) error {
	type result struct {
		task cloneTask
		err  error
	}

	sem := make(chan struct{}, maxConcurrent)
	results := make(chan result, len(tasks))
	var wg sync.WaitGroup

	for _, t := range tasks {
		wg.Add(1)
		go func(task cloneTask) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			var err error
			if task.isCustom {
				err = cloneCustomRepo(reposDir, task.remote, task.destName)
			} else {
				err = cloneRepoAs(reposDir, task.remote, task.destName, task.org)
			}
			results <- result{task: task, err: err}
		}(t)
	}

	go func() {
		wg.Wait()
		close(results)
	}()

	var firstErr error
	for r := range results {
		if r.err != nil && firstErr == nil {
			firstErr = r.err
		}
	}
	return firstErr
}

func cloneRepo(reposDir, repo, org string) error {
	return cloneRepoAs(reposDir, repo, repo, org)
}

func cloneRepoAs(reposDir, remote, destName, org string) error {
	dest := filepath.Join(reposDir, destName)
	if _, err := os.Stat(dest); err == nil {
		fmt.Printf("  ✓ %s (exists)\n", destName)
		return nil
	}

	fmt.Printf("  ⏳ %s...", destName)

	// HTTPS clone (works for public repos, no setup required)
	url := fmt.Sprintf("https://github.com/%s/%s.git", org, remote)
	cmd := exec.Command("git", "clone", "--depth", "1", url, dest)
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Println(" ✗")
		return fmt.Errorf("clone %s: %w", destName, err)
	}
	fmt.Println(" ✓")
	return nil
}

// checkRequiredPackages checks for required system packages.
func checkRequiredPackages() {
	required := []struct {
		name        string
		command     string
		installHelp string
	}{
		{
			name:    "git",
			command: "git",
			installHelp: "macOS: brew install git\n" +
				"      Linux: apt-get install git (Debian/Ubuntu) or yum install git (RHEL/CentOS)\n" +
				"      Windows: https://git-scm.com/download/win",
		},
		{
			name:    "docker",
			command: "docker",
			installHelp: "macOS/Windows: https://www.docker.com/products/docker-desktop\n" +
				"           Linux: https://docs.docker.com/engine/install/",
		},
		{
			name:    "docker-compose",
			command: "docker-compose",
			installHelp: "macOS/Windows: Included with Docker Desktop\n" +
				"            Linux: sudo apt-get install docker-compose (Debian/Ubuntu)",
		},
		{
			name:    "python3",
			command: "python3",
			installHelp: "macOS: brew install python3\n" +
				"      Linux: apt-get install python3 (Debian/Ubuntu) or yum install python3 (RHEL/CentOS)\n" +
				"      Windows: https://www.python.org/downloads/",
		},
		{
			name:    "ripgrep (rg)",
			command: "rg",
			installHelp: "macOS: brew install ripgrep\n" +
				"      Linux: apt-get install ripgrep (Debian/Ubuntu) or yum install ripgrep (RHEL/CentOS)\n" +
				"      Windows: https://github.com/BurntSushi/ripgrep#installation",
		},
	}

	fmt.Println("Checking required packages...")
	var missing []string

	for _, pkg := range required {
		if err := exec.Command("which", pkg.command).Run(); err != nil {
			missing = append(missing, pkg.name)
			fmt.Printf("  ✗ %s (not found)\n", pkg.name)
		} else {
			fmt.Printf("  ✓ %s\n", pkg.name)
		}
	}

	// Check Python packages if python3 is available
	pythonPackages := []struct {
		name        string
		importName  string
		installHelp string
	}{
		{
			name:        "graphify",
			importName:  "graphify",
			installHelp: "pip3 install graphify",
		},
		{
			name:        "nats-py",
			importName:  "nats",
			installHelp: "pip3 install nats-py",
		},
	}

	for _, pkg := range pythonPackages {
		cmd := exec.Command("python3", "-c", fmt.Sprintf("import %s", pkg.importName))
		if err := cmd.Run(); err != nil {
			missing = append(missing, pkg.name)
			fmt.Printf("  ✗ %s (not installed)\n", pkg.name)
		} else {
			fmt.Printf("  ✓ %s\n", pkg.name)
		}
	}

	fmt.Println()

	if len(missing) > 0 {
		fmt.Printf("⚠ Missing required package(s): %v\n\n", missing)
		fmt.Println("Please install the following packages before proceeding:")
		fmt.Println()
		for _, pkg := range required {
			for _, m := range missing {
				if pkg.name == m {
					fmt.Printf("  %s:\n", pkg.name)
					fmt.Printf("    %s\n", pkg.installHelp)
					fmt.Println()
				}
			}
		}
		for _, pkg := range pythonPackages {
			for _, m := range missing {
				if pkg.name == m {
					fmt.Printf("  %s:\n", pkg.name)
					fmt.Printf("    %s\n", pkg.installHelp)
					fmt.Println()
				}
			}
		}
	}
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

// loadCustomBots loads custom bots and mounts from a JSON file
func loadCustomBots(cfg *Config, filePath string) error {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return err
	}

	type CustomBotsFile struct {
		CustomBots   []CustomBot   `json:"custom_bots"`
		CustomMounts []CustomMount `json:"custom_mounts"`
	}

	var cbf CustomBotsFile
	if err := json.Unmarshal(data, &cbf); err != nil {
		return err
	}

	cfg.CustomBots = cbf.CustomBots
	cfg.CustomMounts = cbf.CustomMounts

	fmt.Printf("Loaded %d custom bots and %d custom mounts\n", len(cfg.CustomBots), len(cfg.CustomMounts))
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
		TerminalContext:   cfg.TerminalContext,
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
	cfg.TerminalContext = cf.TerminalContext

	return nil
}

// installTerminalContext downloads and installs the bot-army-shell package.
func installTerminalContext() error {
	// Create config directory
	configDir := filepath.Join(os.Getenv("HOME"), ".config", "bot-army-shell")
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		return fmt.Errorf("create config dir: %w", err)
	}

	// Run the installer script
	fmt.Println("  ⏳ Installing bot-army-shell...")
	installCmd := exec.Command("bash", "-c", "curl -fsSL https://raw.githubusercontent.com/ergon-automation-labs/bot-army-shell/main/install.sh | bash")
	installCmd.Stdout = os.Stdout
	installCmd.Stderr = os.Stderr

	if err := installCmd.Run(); err != nil {
		return fmt.Errorf("run installer: %w", err)
	}

	// Verify installation
	scriptPath := filepath.Join(configDir, "bot-army-context.zsh")
	if _, err := os.Stat(scriptPath); err != nil {
		return fmt.Errorf("verify installation: %w", err)
	}

	return nil
}

