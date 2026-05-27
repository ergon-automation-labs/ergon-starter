package dashboard

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
	"time"
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
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "docker", "ps", "-a", "--format", "{{json .}}")
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
// Docker compose names follow {project}-{service}-{n}, where the project name
// can contain hyphens (e.g. "bot-army-core_pack-1"). Service names contain underscores
// (core_pack, social_media_pack) or are simple words (nats).
// Returns the service name, e.g. "core_pack", "nats".
func ComposeServiceName(name string) string {
	name = strings.TrimPrefix(name, "/")
	// Strip trailing -{replica_number}
	idx := strings.LastIndex(name, "-")
	if idx <= 0 {
		return name
	}
	// Check if the part after the last dash is a number (compose replica)
	for _, c := range name[idx+1:] {
		if c < '0' || c > '9' {
			return name // Not a compose name, return as-is
		}
	}
	projectService := name[:idx]
	// Split on dashes and find the first segment containing an underscore —
	// that's where the service name starts. Services use underscores; project names use dashes.
	parts := strings.Split(projectService, "-")
	for i, part := range parts {
		if strings.Contains(part, "_") {
			return strings.Join(parts[i:], "-")
		}
	}
	// No underscore found — service is a single word (e.g. "nats"), return last segment
	return parts[len(parts)-1]
}

// DockerStats returns container resource usage stats.
// Container names are normalized to compose service names for display.
func DockerStats() ([]DockerStat, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "docker", "stats", "--no-stream", "--format", "{{json .}}")
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
