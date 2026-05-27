package dashboard

import (
	"context"
	"encoding/json"
	"time"

	"github.com/nats-io/nats.go"
)

// HealthStatus represents a bot's NATS health status.
type HealthStatus struct {
	Service string // e.g. "gtd", "core_pack"
	Status  string // "healthy", "degraded", "unhealthy", "unknown"
	Uptime  int    // uptime in seconds
}

// CheckNATSHealth connects to NATS and collects health status for known services.
// It subscribes to "system.health" for a brief window and collects responses.
func CheckNATSHealth(natsURL string, timeout time.Duration) map[string]HealthStatus {
	nc, err := nats.Connect(natsURL, nats.Timeout(2*time.Second))
	if err != nil {
		return nil
	}
	defer nc.Close()

	results := make(map[string]HealthStatus)
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	sub, err := nc.SubscribeSync("system.health")
	if err != nil {
		return results
	}
	defer sub.Unsubscribe()

	// Send an empty request to trigger health responses
	nc.Publish("system.health", nil)

	// Collect responses for the timeout duration
	for {
		msg, err := sub.NextMsgWithContext(ctx)
		if err != nil {
			break
		}
		var envelope map[string]interface{}
		if err := json.Unmarshal(msg.Data, &envelope); err != nil {
			continue
		}
		payload, ok := envelope["payload"].(map[string]interface{})
		if !ok {
			continue
		}
		service, _ := payload["service"].(string)
		status, _ := payload["status"].(string)
		uptime, _ := payload["uptime_seconds"].(float64)
		if service != "" {
			results[service] = HealthStatus{
				Service: service,
				Status:  status,
				Uptime:  int(uptime),
			}
		}
	}

	return results
}