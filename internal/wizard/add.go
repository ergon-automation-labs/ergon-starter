package wizard

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

// RunAdd adds a bot to an existing installation.
func RunAdd(botName string) error {
	allBots, err := LoadBots()
	if err != nil {
		return err
	}

	var bot *Bot
	for _, b := range allBots {
		if b.Name == botName || b.ReleaseName == botName || b.Repo == botName {
			bot = &b
			break
		}
	}
	if bot == nil {
		fmt.Println("Available bots:")
		for _, b := range allBots {
			fmt.Printf("  %-20s %s\n", b.Name, b.Category)
		}
		return fmt.Errorf("unknown bot: %s", botName)
	}

	// Check compose file exists
	composePath := "docker-compose.yml"
	data, err := os.ReadFile(composePath)
	if err != nil {
		return fmt.Errorf("no docker-compose.yml found — run 'bot-army init' first")
	}

	// Check if already present
	if strings.Contains(string(data), bot.ReleaseName+":") {
		return fmt.Errorf("%s is already in docker-compose.yml", bot.Name)
	}

	// Clone repo if needed
	reposDir := "repos"
	if err := cloneRepo(reposDir, bot.Repo, "ergon-automation-labs"); err != nil {
		return err
	}

	// Append service to compose file
	if err := appendService(composePath, data, bot); err != nil {
		return err
	}

	fmt.Printf("\n✓ Added %s\n", bot.Name)
	fmt.Printf("  docker compose up -d --build %s\n", bot.ReleaseName)
	return nil
}

func appendService(composePath string, existing []byte, bot *Bot) error {
	// Parse to check structure, but append as text to preserve formatting
	var compose map[string]interface{}
	if err := yaml.Unmarshal(existing, &compose); err != nil {
		return fmt.Errorf("parse compose: %w", err)
	}

	var service strings.Builder
	service.WriteString(fmt.Sprintf("\n  %s:\n", bot.ReleaseName))
	service.WriteString("    build:\n")
	service.WriteString("      context: ./repos\n")
	service.WriteString("      dockerfile: ../Dockerfile\n")
	service.WriteString("      args:\n")
	service.WriteString(fmt.Sprintf("        BOT_REPO: %s\n", bot.Repo))
	service.WriteString(fmt.Sprintf("        BOT_NAME: %s\n", bot.ReleaseName))
	service.WriteString("    env_file: .env\n")
	service.WriteString("    volumes:\n")
	service.WriteString(fmt.Sprintf("      - ./data/logs/%s:/var/log/bot_army\n", bot.Name))

	deps := []string{"nats"}
	if bot.NeedsDB {
		deps = append(deps, "postgres")
	}
	service.WriteString("    depends_on:\n")
	for _, dep := range deps {
		if dep == "postgres" {
			service.WriteString(fmt.Sprintf("      %s:\n        condition: service_healthy\n", dep))
		} else {
			service.WriteString(fmt.Sprintf("      %s:\n        condition: service_started\n", dep))
		}
	}
	service.WriteString("    restart: unless-stopped\n")

	// Insert before "volumes:" line
	content := string(existing)
	idx := strings.Index(content, "\nvolumes:")
	if idx == -1 {
		// No volumes section, append at end
		content += service.String()
	} else {
		content = content[:idx] + service.String() + content[idx:]
	}

	return os.WriteFile(composePath, []byte(content), 0o644)
}

// RunStatus shows current service state.
func RunStatus() error {
	composePath := "docker-compose.yml"
	if _, err := os.Stat(composePath); err != nil {
		return fmt.Errorf("no docker-compose.yml found — run 'bot-army init' first")
	}

	data, err := os.ReadFile(composePath)
	if err != nil {
		return err
	}

	fmt.Println("Configured services:")

	// Quick parse to list services
	var compose map[string]interface{}
	if err := yaml.Unmarshal(data, &compose); err != nil {
		return err
	}

	services, ok := compose["services"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("no services found")
	}

	infra := []string{}
	bots := []string{}
	for name := range services {
		if name == "nats" || name == "postgres" || name == "ollama" {
			infra = append(infra, name)
		} else {
			bots = append(bots, name)
		}
	}

	fmt.Println("\n  Infrastructure:")
	for _, s := range infra {
		fmt.Printf("    • %s\n", s)
	}
	catalogBots, _ := LoadBots()
	fmt.Println("\n  Bots:")
	for _, s := range bots {
		label := s
		for _, b := range catalogBots {
			if b.ReleaseName == s {
				label = fmt.Sprintf("%-25s v%s (%s)", s, b.Version, b.Category)
				break
			}
		}
		fmt.Printf("    • %s\n", label)
	}

	fmt.Println("\nRun 'docker compose ps' for live status.")

	// Check if .env has missing required vars
	envPath := filepath.Join(".", ".env")
	if _, err := os.Stat(envPath); err == nil {
		envData, _ := os.ReadFile(envPath)
		envContent := string(envData)
		if strings.Contains(envContent, "ANTHROPIC_API_KEY=\n") || strings.Contains(envContent, "# ANTHROPIC_API_KEY=") {
			fmt.Println("\n⚠  ANTHROPIC_API_KEY not set in .env")
		}
	}

	return nil
}
