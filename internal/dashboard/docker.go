package dashboard

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

// DockerContainer represents a container from docker ps.
type DockerContainer struct {
	ID      string `json:"ID"`
	Names   string `json:"Names"`
	Image   string `json:"Image"`
	Status  string `json:"Status"`
	State   string `json:"State"`
	Ports   string `json:"Ports"`
	Created string `json:"CreatedAt"`
}

// DockerStat represents container stats from docker stats.
type DockerStat struct {
	Container string `json:"Container"`
	Name      string `json:"Name"`
	CPUPerc   string `json:"CPUPerc"`
	MemUsage  string `json:"MemUsage"`
	MemLimit  string `json:"MemLimit"`
	NetIO     string `json:"NetIO"`
	BlockIO   string `json:"BlockIO"`
	PidCount  string `json:"Pids"`
}

// DockerPS returns a list of running/stopped containers.
// Container names are normalized to compose service names.
func DockerPS() ([]DockerContainer, error) {
	cmd := exec.Command("docker", "ps", "-a", "--format", "{{json .}}")
	output, err := cmd.Output()
	if err != nil {
		return nil, err
	}

	var containers []DockerContainer
	for _, line := range strings.Split(strings.TrimSpace(string(output)), "\n") {
		if line == "" {
			continue
		}
		var c DockerContainer
		if err := json.Unmarshal([]byte(line), &c); err != nil {
			continue // skip malformed lines
		}
		c.Names = ComposeServiceName(c.Names)
		containers = append(containers, c)
	}

	return containers, nil
}

// ComposeServiceName extracts the service name from a docker compose container name.
// Docker compose names follow {project}-{service}-{n}, e.g. "workspace-core_pack-1" → "core_pack".
// Standalone container names (no compose pattern) are returned as-is.
func ComposeServiceName(name string) string {
	name = strings.TrimPrefix(name, "/")
	if idx := strings.LastIndex(name, "-"); idx > 0 {
		if _, err := strconv.Atoi(name[idx+1:]); err == nil {
			serviceWithProject := name[:idx]
			if dotIdx := strings.Index(serviceWithProject, "-"); dotIdx >= 0 {
				return serviceWithProject[dotIdx+1:]
			}
			return serviceWithProject
		}
	}
	return name
}

// DockerStats returns container resource usage stats.
// Container names are normalized to compose service names for display.
func DockerStats() ([]DockerStat, error) {
	cmd := exec.Command("docker", "stats", "--no-stream", "--format", "{{json .}}")
	output, err := cmd.Output()
	if err != nil {
		return nil, err
	}

	var stats []DockerStat
	for _, line := range strings.Split(strings.TrimSpace(string(output)), "\n") {
		if line == "" {
			continue
		}
		var s DockerStat
		if err := json.Unmarshal([]byte(line), &s); err != nil {
			continue // skip malformed lines
		}
		s.Name = ComposeServiceName(s.Name)
		stats = append(stats, s)
	}

	return stats, nil
}

// DockerLogs returns the last N lines of a container's logs.
func DockerLogs(containerName string, tail int) (string, error) {
	cmd := exec.Command("docker", "logs", "--tail", fmt.Sprintf("%d", tail), containerName)
	output, err := cmd.CombinedOutput()
	return string(output), err
}

// DockerLogsFollow streams logs from a container until the context is cancelled.
func DockerLogsFollow(ctx context.Context, containerName string, tail int, callback func(string)) error {
	cmd := exec.CommandContext(ctx, "docker", "logs", "-f", "--tail", fmt.Sprintf("%d", tail), containerName)
	pipe, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	defer pipe.Close()

	if err := cmd.Start(); err != nil {
		return err
	}

	scanner := bufio.NewScanner(pipe)
	for scanner.Scan() {
		line := scanner.Text()
		callback(line)
	}

	return cmd.Wait()
}
