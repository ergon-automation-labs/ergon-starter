package wizard

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

type Bot struct {
	Name        string   `json:"name"`
	App         string   `json:"app"`
	ReleaseName string   `json:"release_name"`
	Repo        string   `json:"repo"`
	Remote      string   `json:"remote"`
	Version     string   `json:"version"`
	NeedsDB     bool     `json:"needs_db"`
	Category    string   `json:"category"`
	EnvVars     []EnvVar `json:"env_vars"`
}

func (b Bot) DisplayName() string {
	return b.Name
}

func (b Bot) IsCore() bool {
	return b.Category == "core" || b.Category == "primary"
}

type EnvVar struct {
	Key      string `json:"key"`
	Prompt   string `json:"prompt,omitempty"`
	Default  string `json:"default,omitempty"`
	Required bool   `json:"required,omitempty"`
	Secret   bool   `json:"secret"`
}

type Provider struct {
	Name        string   `json:"name"`
	Label       string   `json:"label"`
	EnvVars     []EnvVar `json:"env_vars"`
	CanSelfHost bool     `json:"can_self_host,omitempty"`
}

type Pack struct {
	Name        string   `json:"name"`
	Description string   `json:"description"`
	ReleaseName string   `json:"release_name"`
	Bots        []string `json:"bots"`
}

// LoadBots reads the bot catalog from catalog/bots.json.
// Looks next to the binary first, then in the working directory.
func LoadBots() ([]Bot, error) {
	paths := []string{
		catalogPath("bots.json"),
		"catalog/bots.json",
	}

	for _, p := range paths {
		data, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		var bots []Bot
		if err := json.Unmarshal(data, &bots); err != nil {
			return nil, fmt.Errorf("parse %s: %w", p, err)
		}
		// Backfill prompts from key names
		for i := range bots {
			for j := range bots[i].EnvVars {
				if bots[i].EnvVars[j].Prompt == "" {
					bots[i].EnvVars[j].Prompt = bots[i].EnvVars[j].Key
				}
				if bots[i].EnvVars[j].Secret {
					bots[i].EnvVars[j].Required = true
				}
			}
		}
		return bots, nil
	}

	return nil, fmt.Errorf("catalog/bots.json not found — run 'make sync' first")
}

// LoadPacks reads the bot packs from catalog/packs.json.
func LoadPacks() ([]Pack, error) {
	paths := []string{
		catalogPath("packs.json"),
		"catalog/packs.json",
	}

	for _, p := range paths {
		data, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		var packs []Pack
		if err := json.Unmarshal(data, &packs); err != nil {
			return nil, fmt.Errorf("parse %s: %w", p, err)
		}
		return packs, nil
	}

	return nil, fmt.Errorf("catalog/packs.json not found")
}

// BotPackMap builds a map from bot name to pack name.
func BotPackMap(packs []Pack) map[string]string {
	m := make(map[string]string)
	for _, pack := range packs {
		for _, botName := range pack.Bots {
			m[botName] = pack.Name
		}
	}
	return m
}

func catalogPath(name string) string {
	exe, err := os.Executable()
	if err != nil {
		return filepath.Join("catalog", name)
	}
	return filepath.Join(filepath.Dir(exe), "catalog", name)
}

// Providers are relatively stable — keep in code.
// The sync script handles the bot list which changes often.
var Providers = []Provider{
	{
		Name:        "ollama",
		Label:       "Ollama (local, no API key)",
		CanSelfHost: true,
		EnvVars: []EnvVar{
			{Key: "OLLAMA_BASE_URL", Prompt: "Ollama URL", Default: "http://host.docker.internal:11434"},
			{Key: "OLLAMA_MODEL_LIGHT", Prompt: "Light model", Default: "llama3.1"},
			{Key: "OLLAMA_MODEL_MEDIUM", Prompt: "Medium model", Default: "llama3.1"},
		},
	},
	{
		Name:  "anthropic",
		Label: "Anthropic (Claude)",
		EnvVars: []EnvVar{
			{Key: "ANTHROPIC_API_KEY", Prompt: "API key", Required: true, Secret: true},
			{Key: "ANTHROPIC_MODEL_HEAVY", Prompt: "Heavy model", Default: "claude-sonnet-4-20250514"},
		},
	},
	{
		Name:  "openrouter",
		Label: "OpenRouter (multi-model gateway)",
		EnvVars: []EnvVar{
			{Key: "OPENROUTER_API_KEY", Prompt: "API key", Required: true, Secret: true},
			{Key: "OPENROUTER_MODEL_LIGHT", Prompt: "Light model", Default: "meta-llama/llama-3.1-8b-instruct"},
			{Key: "OPENROUTER_MODEL_MEDIUM", Prompt: "Medium model", Default: "anthropic/claude-sonnet-4-20250514"},
			{Key: "OPENROUTER_MODEL_HEAVY", Prompt: "Heavy model", Default: "anthropic/claude-sonnet-4-20250514"},
		},
	},
	{
		Name:  "openai",
		Label: "OpenAI (GPT)",
		EnvVars: []EnvVar{
			{Key: "OPENAI_API_KEY", Prompt: "API key", Required: true, Secret: true},
			{Key: "OPENAI_MODEL_LIGHT", Prompt: "Light model", Default: "gpt-4o-mini"},
			{Key: "OPENAI_MODEL_MEDIUM", Prompt: "Medium model", Default: "gpt-4o"},
			{Key: "OPENAI_MODEL_HEAVY", Prompt: "Heavy model", Default: "gpt-4o"},
		},
	},
}
