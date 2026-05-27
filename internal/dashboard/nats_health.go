package dashboard

import (
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/nats-io/nats.go"
)

// HealthStatus represents a bot's NATS health status.
type HealthStatus struct {
	Service string // e.g. "gtd", "core_pack"
	Status  string // "healthy", "degraded", "unhealthy", "unknown"
	Uptime  int    // uptime in seconds
}

// NATSHealthMonitor maintains a persistent NATS subscription for
// system.health beacons and caches the latest status per service.
type NATSHealthMonitor struct {
	nc      *nats.Conn
	health  map[string]HealthStatus
	mu      sync.RWMutex
	sub     *nats.Subscription
	NATSPort string
}

// NewNATSHealthMonitor creates a new health monitor that tries to connect to NATS.
func NewNATSHealthMonitor(natsPort string) *NATSHealthMonitor {
	return &NATSHealthMonitor{
		health:   make(map[string]HealthStatus),
		NATSPort: natsPort,
	}
}

// Connect tries to connect to NATS and subscribe to system.health.
// Safe to call repeatedly (e.g. on refresh) — reconnects if needed.
func (m *NATSHealthMonitor) Connect() error {
	if m.nc != nil && m.nc.IsConnected() {
		return nil
	}

	// Close old connection if any
	if m.nc != nil {
		m.nc.Close()
	}

	// Try both host.docker.internal (from Docker) and localhost (from host)
	urls := []string{
		fmt.Sprintf("nats://host.docker.internal:%s", m.NATSPort),
		fmt.Sprintf("nats://localhost:%s", m.NATSPort),
	}

	var nc *nats.Conn
	var err error
	for _, url := range urls {
		nc, err = nats.Connect(url, nats.Timeout(2*time.Second))
		if err == nil {
			break
		}
	}
	if err != nil {
		return err
	}

	m.nc = nc

	// Subscribe to system.health beacons
	sub, err := nc.Subscribe("system.health", func(msg *nats.Msg) {
		var envelope map[string]interface{}
		if err := json.Unmarshal(msg.Data, &envelope); err != nil {
			return
		}
		payload, ok := envelope["payload"].(map[string]interface{})
		if !ok {
			return
		}
		service, _ := payload["service"].(string)
		status, _ := payload["status"].(string)
		uptime, _ := payload["uptime_seconds"].(float64)
		if service != "" {
			m.mu.Lock()
			m.health[service] = HealthStatus{
				Service: service,
				Status:  status,
				Uptime:  int(uptime),
			}
			m.mu.Unlock()
		}
	})
	if err != nil {
		return err
	}
	m.sub = sub

	return nil
}

// GetHealth returns the latest cached health status per service.
func (m *NATSHealthMonitor) GetHealth() map[string]HealthStatus {
	m.mu.RLock()
	defer m.mu.RUnlock()

	// Return a copy
	result := make(map[string]HealthStatus, len(m.health))
	for k, v := range m.health {
		result[k] = v
	}
	return result
}

// Connected returns whether the monitor has an active NATS connection.
func (m *NATSHealthMonitor) Connected() bool {
	return m.nc != nil && m.nc.IsConnected()
}

// Close shuts down the NATS connection.
func (m *NATSHealthMonitor) Close() {
	if m.sub != nil {
		m.sub.Unsubscribe()
	}
	if m.nc != nil {
		m.nc.Close()
	}
}

// MatchService maps a NATS health service name to a bot release name.
// Health beacons use short names ("gtd", "para") but the dashboard uses
// release names ("gtd_bot", "core_pack"). This maps both ways.
func MatchService(healthMap map[string]HealthStatus, releaseName string) (HealthStatus, bool) {
	// Direct match (e.g. "core_pack" → "core_pack")
	if h, ok := healthMap[releaseName]; ok {
		return h, true
	}

	// Strip _bot/_pack suffix and try (e.g. "gtd_bot" → try "gtd")
	shortName := strings.TrimSuffix(releaseName, "_bot")
	shortName = strings.TrimSuffix(shortName, "_pack")
	if h, ok := healthMap[shortName]; ok {
		return h, true
	}

	return HealthStatus{}, false
}