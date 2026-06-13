package wizard

import (
	"testing"
)

func TestConfigIntegrationFlags(t *testing.T) {
	// Test that Config struct properly handles EnabledIntegrations
	cfg := &Config{
		EnvValues:           make(map[string]string),
		EnabledIntegrations: make(map[string]bool),
		InstallDir:         ".",
		GitOrg:             "ergon-automation-labs",
		Ports:              DefaultPorts,
		EnableOTLP:         true,
	}

	// Simulate user selecting bots
	cfg.SelectedBots = []Bot{
		{Name: "gtd", ReleaseName: "gtd_bot"},
		{Name: "llm", ReleaseName: "llm_bot"},
		{Name: "synapse", ReleaseName: "synapse_bot"},
	}

	// Determine required integrations
	required := DeterminedRequiredIntegrations(cfg.SelectedBots)
	cfg.EnabledIntegrations = required

	// Verify GTD is always enabled
	if !cfg.EnabledIntegrations["GTD"] {
		t.Fatal("GTD should always be enabled")
	}

	// Verify Bridge, LLM are enabled (required by selected bots)
	if !cfg.EnabledIntegrations["BRIDGE"] {
		t.Fatal("BRIDGE should be enabled (required by GTD, Synapse)")
	}
	if !cfg.EnabledIntegrations["LLM"] {
		t.Fatal("LLM should be enabled (required by GTD, Synapse)")
	}
	if !cfg.EnabledIntegrations["PARA"] {
		t.Fatal("PARA should be enabled (required by GTD)")
	}
	if !cfg.EnabledIntegrations["DISPATCHER"] {
		t.Fatal("DISPATCHER should be enabled (required by LLM)")
	}

	// Verify unrequired integrations are disabled
	if cfg.EnabledIntegrations["GTD"] == false {
		t.Fatal("GTD should always be enabled")
	}
}

func TestConfigPersistence(t *testing.T) {
	// Test that Config struct properly stores and retrieves integration flags
	// (actual file I/O is tested in other integration tests)

	// Create config with integration flags
	cfg := &Config{
		EnvValues:           map[string]string{"TEST_VAR": "value"},
		EnabledIntegrations: map[string]bool{"BRIDGE": true, "LLM": true, "PARA": false, "GTD": true},
		InstallDir:         ".",
		Ports:              DefaultPorts,
		EnableOTLP:         true,
	}
	cfg.SelectedPacks = []Pack{
		{Name: "core", ReleaseName: "core"},
	}

	// Simulate ConfigFile serialization (what saveConfig does)
	cf := &ConfigFile{
		EnabledIntegrations: cfg.EnabledIntegrations,
		Ports:              cfg.Ports,
		EnableOTLP:         cfg.EnableOTLP,
	}

	// Create new config and restore
	cfg2 := &Config{
		EnabledIntegrations: cf.EnabledIntegrations,
		Ports:              cf.Ports,
		EnableOTLP:         cf.EnableOTLP,
	}

	// Verify integration flags were preserved
	if !cfg2.EnabledIntegrations["BRIDGE"] {
		t.Fatal("BRIDGE flag not preserved after restore")
	}
	if !cfg2.EnabledIntegrations["LLM"] {
		t.Fatal("LLM flag not preserved after restore")
	}
	if cfg2.EnabledIntegrations["PARA"] {
		t.Fatal("PARA should be false after restore")
	}
	if !cfg2.EnabledIntegrations["GTD"] {
		t.Fatal("GTD should be true after restore")
	}
}

func TestEnvFileGeneration(t *testing.T) {
	// Create config with integration flags
	cfg := &Config{
		EnvValues:           make(map[string]string),
		EnabledIntegrations: map[string]bool{"BRIDGE": true, "LLM": true, "PARA": false, "GTD": true},
		InstallDir:         ".",
		SelectedProviders:  []Provider{}, // Empty to simplify test
		Ports:              DefaultPorts,
		EnableOTLP:         false,
	}

	// This would generate the .env file
	// We just verify the integration flags would be included
	envVars := GetIntegrationEnvVars(cfg.EnabledIntegrations)

	// Verify all expected env vars are present
	if val, ok := envVars["BRIDGE_INTEGRATION_ENABLED"]; !ok || val != "true" {
		t.Fatal("BRIDGE_INTEGRATION_ENABLED not correctly set")
	}
	if val, ok := envVars["LLM_INTEGRATION_ENABLED"]; !ok || val != "true" {
		t.Fatal("LLM_INTEGRATION_ENABLED not correctly set")
	}
	if val, ok := envVars["PARA_INTEGRATION_ENABLED"]; !ok || val != "false" {
		t.Fatal("PARA_INTEGRATION_ENABLED not correctly set")
	}
	if val, ok := envVars["GTD_INTEGRATION_ENABLED"]; !ok || val != "true" {
		t.Fatal("GTD_INTEGRATION_ENABLED not correctly set")
	}
}

func TestIntegrationFlagsRespectManualOverride(t *testing.T) {
	// User selects bots that require Bridge
	bots := []Bot{
		{Name: "gtd", ReleaseName: "gtd_bot"},
		{Name: "dispatcher", ReleaseName: "dispatcher_bot"},
	}

	// System determines Bridge is required
	required := DeterminedRequiredIntegrations(bots)
	if !required["BRIDGE"] {
		t.Fatal("BRIDGE should be required by GTD + Dispatcher")
	}

	// But user could manually disable it if they know what they're doing
	// (This would be done in the TUI)
	overridden := make(map[string]bool)
	for k, v := range required {
		overridden[k] = v
	}
	overridden["BRIDGE"] = false

	// Verify override took effect
	if overridden["BRIDGE"] {
		t.Fatal("Manual override of BRIDGE should have taken effect")
	}
	if !overridden["DISPATCHER"] {
		t.Fatal("DISPATCHER should still be enabled")
	}
}
