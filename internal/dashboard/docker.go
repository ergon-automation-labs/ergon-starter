package dashboard

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
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
		containers = append(containers, c)
	}

	return containers, nil
}

// DockerStats returns container resource usage stats.
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
