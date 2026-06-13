package wizard

// IntegrationMapping defines which bots require which integrations
// Based on Phase 3 integration gating analysis

var BotIntegrationRequirements = map[string][]string{
	// Core bots
	"gtd_bot": {"BRIDGE", "PARA", "CONTEXT", "NOTIFICATION", "LLM"},
	"llm_bot": {"DISPATCHER"},
	"dispatcher_bot": {"BRIDGE", "PARA", "CONTEXT", "DISPATCHER"},
	"para_bot": {"PARA"},
	"general_purpose_bot": {"PARA", "LLM", "SYNAPSE"},

	// Social/Discord
	"synapse_bot": {"BRIDGE", "LLM", "SYNAPSE", "CONTEXT", "NOTIFICATION"},
	"bridge_lite_bot": {"BRIDGE"},

	// Observability/Management
	"graphify_cache_bot": {},
	"job_scheduler_bot": {"SYNAPSE", "DISPATCHER"},
	"skills_bot": {"BRIDGE", "PARA", "SYNAPSE"},
	"surface_mcp_bot": {},
	"elixir_tools_mcp_bot": {},

	// Optional packs
	"fitness_bot": {"CONTEXT", "NOTIFICATION", "PARA"},
	"chore_bot": {"NOTIFICATION"},
	"rpg_bot": {"PARA"},

	"youtube_manager_bot": {},
	"media_ingestion_bot": {},

	"terrain_bot": {"LLM"},
	"internal_docs_bot": {"PARA"},

	"feeds_bot": {},
	"rss_polling_bot": {},
	"job_applications_bot": {"LLM"},
}

// AllIntegrations lists all available integrations
var AllIntegrations = []string{
	"BRIDGE",
	"LLM",
	"PARA",
	"CONTEXT",
	"NOTIFICATION",
	"SYNAPSE",
	"DISPATCHER",
	"GTD",
}

// IntegrationDescription provides human-readable descriptions
var IntegrationDescriptions = map[string]string{
	"BRIDGE": "Claude Bridge - Central AI interface",
	"LLM": "LLM Services - AI/ML processing",
	"PARA": "PARA System - Knowledge persistence",
	"CONTEXT": "Context Broker - System state queries",
	"NOTIFICATION": "Notifications - User alerts and messages",
	"SYNAPSE": "Synapse - Discord/social integration",
	"DISPATCHER": "Dispatcher - AI orchestration",
	"GTD": "GTD - Task management system",
}

// DeterminedRequiredIntegrations returns the set of integrations required for the selected bots
func DeterminedRequiredIntegrations(bots []Bot) map[string]bool {
	required := make(map[string]bool)

	for _, bot := range bots {
		reqs, exists := BotIntegrationRequirements[bot.ReleaseName]
		if exists {
			for _, req := range reqs {
				required[req] = true
			}
		}
	}

	// GTD is always required (core system)
	required["GTD"] = true

	return required
}

// IntegrationToEnvVar converts integration name to environment variable
func IntegrationToEnvVar(integration string) string {
	return integration + "_INTEGRATION_ENABLED"
}

// GetIntegrationEnvVars returns a map of integration env vars (all enabled by default)
func GetIntegrationEnvVars(enabledIntegrations map[string]bool) map[string]string {
	envVars := make(map[string]string)

	for _, integration := range AllIntegrations {
		envVar := IntegrationToEnvVar(integration)
		if enabledIntegrations[integration] {
			envVars[envVar] = "true"
		} else {
			envVars[envVar] = "false"
		}
	}

	return envVars
}
