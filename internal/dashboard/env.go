package dashboard

import (
	"fmt"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
)

// ParseEnvFile reads and parses a .env file.
func ParseEnvFile(path string) (map[string]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	env := make(map[string]string)
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			key := strings.TrimSpace(parts[0])
			val := strings.TrimSpace(parts[1])
			env[key] = val
		}
	}

	return env, nil
}

// DashboardConfigFromEnv reads .env and docker-compose.yml to build a DashboardConfig.
func DashboardConfigFromEnv(dir string) (*DashboardConfig, error) {
	// Read .env
	envPath := dir + "/.env"
	env, err := ParseEnvFile(envPath)
	if err != nil {
		return nil, fmt.Errorf("read .env: %w", err)
	}

	// Read docker-compose.yml
	composePath := dir + "/docker-compose.yml"
	composeData, err := os.ReadFile(composePath)
	if err != nil {
		return nil, fmt.Errorf("read docker-compose.yml: %w", err)
	}

	// Parse compose YAML
	var compose map[string]interface{}
	if err := yaml.Unmarshal(composeData, &compose); err != nil {
		return nil, fmt.Errorf("parse docker-compose.yml: %w", err)
	}

	// Extract services
	var bots []BotInfo
	services, ok := compose["services"].(map[string]interface{})
	if ok {
		for serviceName := range services {
			// Skip infrastructure services
			if serviceName == "nats" || serviceName == "postgres" || serviceName == "ollama" {
				continue
			}

			// Extract bot info from service name (e.g., "gtd_bot" → name="gtd", releaseName="gtd_bot")
			parts := strings.Split(serviceName, "_")
			if len(parts) >= 2 && parts[len(parts)-1] == "bot" {
				name := strings.Join(parts[:len(parts)-1], "_")
				bots = append(bots, BotInfo{
					Name:        name,
					ReleaseName: serviceName,
				})
			}
		}
	}

	// Get ports from .env
	natsPort := env["STARTER_NATS_PORT"]
	if natsPort == "" {
		natsPort = "54222"
	}

	postgresPort := env["STARTER_POSTGRES_PORT"]
	if postgresPort == "" {
		postgresPort = "55432"
	}

	return &DashboardConfig{
		NATSPort:     natsPort,
		PostgresPort: postgresPort,
		Bots:         bots,
		DataDir:      dir + "/data/logs/",
	}, nil
}
