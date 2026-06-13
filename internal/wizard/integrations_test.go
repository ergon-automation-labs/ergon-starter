package wizard

import (
	"testing"
)

func TestBotIntegrationRequirements(t *testing.T) {
	// Test that bot requirements are defined
	if len(BotIntegrationRequirements) == 0 {
		t.Fatal("BotIntegrationRequirements should not be empty")
	}

	// Test a few known bots
	tests := []struct {
		bot      string
		expected []string
	}{
		{"gtd_bot", []string{"BRIDGE", "PARA", "CONTEXT", "NOTIFICATION", "LLM"}},
		{"synapse_bot", []string{"BRIDGE", "LLM", "SYNAPSE", "CONTEXT", "NOTIFICATION"}},
		{"dispatcher_bot", []string{"BRIDGE", "PARA", "CONTEXT", "DISPATCHER"}},
		{"para_bot", []string{"PARA"}},
	}

	for _, test := range tests {
		reqs, ok := BotIntegrationRequirements[test.bot]
		if !ok {
			t.Errorf("Bot %s not found in requirements", test.bot)
			continue
		}

		if len(reqs) != len(test.expected) {
			t.Errorf("Bot %s: expected %d integrations, got %d", test.bot, len(test.expected), len(reqs))
		}

		// Check each expected integration
		for _, exp := range test.expected {
			found := false
			for _, req := range reqs {
				if req == exp {
					found = true
					break
				}
			}
			if !found {
				t.Errorf("Bot %s: missing expected integration %s", test.bot, exp)
			}
		}
	}
}

func TestAllIntegrations(t *testing.T) {
	// Test that all integration constants are defined
	expected := []string{"BRIDGE", "LLM", "PARA", "CONTEXT", "NOTIFICATION", "SYNAPSE", "DISPATCHER", "GTD"}

	if len(AllIntegrations) != len(expected) {
		t.Errorf("Expected %d integrations, got %d", len(expected), len(AllIntegrations))
	}

	for _, exp := range expected {
		found := false
		for _, integ := range AllIntegrations {
			if integ == exp {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("Missing integration: %s", exp)
		}
	}
}

func TestIntegrationToEnvVar(t *testing.T) {
	tests := []struct {
		integration string
		expected    string
	}{
		{"BRIDGE", "BRIDGE_INTEGRATION_ENABLED"},
		{"LLM", "LLM_INTEGRATION_ENABLED"},
		{"PARA", "PARA_INTEGRATION_ENABLED"},
		{"GTD", "GTD_INTEGRATION_ENABLED"},
	}

	for _, test := range tests {
		result := IntegrationToEnvVar(test.integration)
		if result != test.expected {
			t.Errorf("IntegrationToEnvVar(%s): expected %s, got %s", test.integration, test.expected, result)
		}
	}
}

func TestDeterminedRequiredIntegrations(t *testing.T) {
	// Create test bots
	bots := []Bot{
		{Name: "gtd", ReleaseName: "gtd_bot"},
		{Name: "para", ReleaseName: "para_bot"},
	}

	result := DeterminedRequiredIntegrations(bots)

	// Check that GTD is always required
	if !result["GTD"] {
		t.Error("GTD should always be required")
	}

	// Check that required integrations from both bots are present
	expectedIntegrations := map[string]bool{
		"BRIDGE":       true,
		"PARA":         true,
		"CONTEXT":      true,
		"NOTIFICATION": true,
		"LLM":          true,
		"GTD":          true,
	}

	for integ, expected := range expectedIntegrations {
		if result[integ] != expected {
			t.Errorf("Expected %s to be %v, got %v", integ, expected, result[integ])
		}
	}

	// Check that unrequired integrations are false
	if result["SYNAPSE"] || result["DISPATCHER"] {
		t.Error("SYNAPSE and DISPATCHER should not be required for GTD+PARA")
	}
}

func TestGetIntegrationEnvVars(t *testing.T) {
	enabled := map[string]bool{
		"BRIDGE": true,
		"LLM":    true,
		"PARA":   false,
		"GTD":    true,
	}

	result := GetIntegrationEnvVars(enabled)

	// Check expected env vars
	tests := []struct {
		key      string
		expected string
	}{
		{"BRIDGE_INTEGRATION_ENABLED", "true"},
		{"LLM_INTEGRATION_ENABLED", "true"},
		{"PARA_INTEGRATION_ENABLED", "false"},
		{"GTD_INTEGRATION_ENABLED", "true"},
		{"CONTEXT_INTEGRATION_ENABLED", "false"},
	}

	for _, test := range tests {
		val, ok := result[test.key]
		if !ok {
			t.Errorf("Missing env var: %s", test.key)
			continue
		}
		if val != test.expected {
			t.Errorf("%s: expected %s, got %s", test.key, test.expected, val)
		}
	}
}

func TestIntegrationDescriptions(t *testing.T) {
	// Check that all integrations have descriptions
	for _, integ := range AllIntegrations {
		if _, ok := IntegrationDescriptions[integ]; !ok {
			t.Errorf("Missing description for integration: %s", integ)
		}
	}
}
