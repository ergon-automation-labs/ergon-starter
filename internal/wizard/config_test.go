package wizard

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestConfigSaveAndLoad(t *testing.T) {
	// Create temp dir
	tmpDir := filepath.Join(os.TempDir(), "bot-army-test-"+time.Now().Format("20060102150405"))
	os.MkdirAll(tmpDir, 0o755)
	defer os.RemoveAll(tmpDir)

	// Create a config
	cfg := &Config{
		EnvValues:  map[string]string{"KEY1": "value1"},
		InstallDir: tmpDir,
		Ports: PortMap{
			NATS:        "54222",
			NATSMonitor: "58222",
			Postgres:    "55432",
			Ollama:      "51434",
		},
		ProviderChain:  "ollama",
		SelfHostOllama: true,
	}

	// Add some bots
	cfg.SelectedBots = []Bot{
		{Name: "gtd", ReleaseName: "gtd_bot"},
		{Name: "bridge", ReleaseName: "bridge_bot"},
	}

	// Add some packs
	cfg.SelectedPacks = []Pack{
		{Name: "primary", Description: "Core bots"},
	}

	// Add providers
	cfg.SelectedProviders = []Provider{
		{Name: "ollama", Label: "Ollama"},
	}

	// Save config
	if err := saveConfig(cfg); err != nil {
		t.Fatalf("saveConfig failed: %v", err)
	}

	// Verify file exists
	configPath := filepath.Join(tmpDir, ".bot-army.json")
	if _, err := os.Stat(configPath); err != nil {
		t.Fatalf("Config file not created: %v", err)
	}

	// Read and parse the JSON
	data, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("Failed to read config file: %v", err)
	}

	var cf ConfigFile
	if err := json.Unmarshal(data, &cf); err != nil {
		t.Fatalf("Failed to parse config JSON: %v", err)
	}

	// Verify fields
	if len(cf.SelectedBotNames) != 2 {
		t.Errorf("Expected 2 bots, got %d", len(cf.SelectedBotNames))
	}
	if cf.SelectedBotNames[0] != "gtd" {
		t.Errorf("Expected first bot 'gtd', got %s", cf.SelectedBotNames[0])
	}
	if cf.Ports.NATS != "54222" {
		t.Errorf("Expected NATS port 54222, got %s", cf.Ports.NATS)
	}
	if cf.ProviderChain != "ollama" {
		t.Errorf("Expected provider chain 'ollama', got %s", cf.ProviderChain)
	}

	// Load into new config
	cfg2 := &Config{
		EnvValues:  make(map[string]string),
		InstallDir: tmpDir,
		AllBots: []Bot{
			{Name: "gtd", ReleaseName: "gtd_bot"},
			{Name: "bridge", ReleaseName: "bridge_bot"},
			{Name: "llm", ReleaseName: "llm_bot"},
		},
	}

	if err := loadConfigInto(cfg2, configPath); err != nil {
		t.Fatalf("loadConfigInto failed: %v", err)
	}

	// Verify loaded config
	if len(cfg2.SelectedBots) != 2 {
		t.Errorf("Expected 2 loaded bots, got %d", len(cfg2.SelectedBots))
	}
	if cfg2.Ports.Postgres != "55432" {
		t.Errorf("Expected Postgres port 55432, got %s", cfg2.Ports.Postgres)
	}
}

func TestBotPackMap(t *testing.T) {
	packs := []Pack{
		{
			Name: "primary",
			Bots: []string{"gtd", "bridge", "dispatcher"},
		},
		{
			Name: "background",
			Bots: []string{"llm", "learning", "terrain"},
		},
	}

	m := BotPackMap(packs)

	// Test lookups
	tests := map[string]string{
		"gtd":        "primary",
		"bridge":     "primary",
		"llm":        "background",
		"learning":   "background",
		"nonexistent": "",
	}

	for botName, expectedPack := range tests {
		actual := m[botName]
		if actual != expectedPack {
			t.Errorf("BotPackMap(%s) = %s, want %s", botName, actual, expectedPack)
		}
	}
}

func TestLoadBots(t *testing.T) {
	// This test requires catalog/bots.json to exist
	bots, err := LoadBots()
	if err != nil {
		t.Logf("LoadBots failed (catalog may not exist): %v", err)
		return // Skip if catalog not available
	}

	if len(bots) == 0 {
		t.Error("Expected bots in catalog, got 0")
	}

	// Verify required fields
	for i, bot := range bots {
		if bot.Name == "" {
			t.Errorf("Bot %d has empty Name", i)
		}
		if bot.ReleaseName == "" {
			t.Errorf("Bot %d (%s) has empty ReleaseName", i, bot.Name)
		}
		if bot.Repo == "" {
			t.Errorf("Bot %d (%s) has empty Repo", i, bot.Name)
		}
	}

	t.Logf("✓ Loaded %d bots from catalog", len(bots))
}

func TestLoadPacks(t *testing.T) {
	// This test requires catalog/packs.json to exist
	packs, err := LoadPacks()
	if err != nil {
		t.Logf("LoadPacks failed (catalog may not exist): %v", err)
		return // Skip if catalog not available
	}

	if len(packs) == 0 {
		t.Error("Expected packs in catalog, got 0")
	}

	// Verify required fields
	for i, pack := range packs {
		if pack.Name == "" {
			t.Errorf("Pack %d has empty Name", i)
		}
		if len(pack.Bots) == 0 {
			t.Errorf("Pack %d (%s) has no bots", i, pack.Name)
		}
	}

	t.Logf("✓ Loaded %d packs from catalog", len(packs))
}
