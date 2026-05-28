package dashboard

import (
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
// Falls back to defaults if files are missing (e.g. before running init).
func DashboardConfigFromEnv(dir string) (*DashboardConfig, error) {
	envPath := dir + "/.env"
	composePath := dir + "/docker-compose.yml"

	env := make(map[string]string)
	envData, err := os.ReadFile(envPath)
	if err == nil {
		for _, line := range strings.Split(string(envData), "\n") {
			line = strings.TrimSpace(line)
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			parts := strings.SplitN(line, "=", 2)
			if len(parts) == 2 {
				env[strings.TrimSpace(parts[0])] = strings.TrimSpace(parts[1])
			}
		}
	}

	natsPort := env["STARTER_NATS_PORT"]
	if natsPort == "" {
		natsPort = "54222"
	}

	postgresPort := env["STARTER_POSTGRES_PORT"]
	if postgresPort == "" {
		postgresPort = "5432"
	}

	mcpPort := env["STARTER_MCP_PORT"]
	if mcpPort == "" {
		mcpPort = "39900"
	}

	var bots []BotInfo

	composeData, err := os.ReadFile(composePath)
	if err == nil {
		var compose map[string]interface{}
		if err := yaml.Unmarshal(composeData, &compose); err == nil {
			services, ok := compose["services"].(map[string]interface{})
			if ok {
				for serviceName := range services {
					if serviceName == "nats" || serviceName == "postgres" || serviceName == "ollama" {
						continue
					}
					parts := strings.Split(serviceName, "_")
					suffix := parts[len(parts)-1]
					if suffix == "bot" || suffix == "pack" {
						name := strings.Join(parts[:len(parts)-1], "_")
						bots = append(bots, BotInfo{
							Name:        name,
							ReleaseName: serviceName,
						})
					}
				}
			}
		}
	}

	return &DashboardConfig{
		NATSPort:     natsPort,
		PostgresPort: postgresPort,
		MCPPort:      mcpPort,
		Bots:         bots,
		DataDir:      dir + "/data/logs/",
	}, nil
}