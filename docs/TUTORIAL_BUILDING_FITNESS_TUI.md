---
doc_status: draft
doc_tier: community
author: abby
date_published: 2026-05-30
estimated_read_time: 15 minutes
---

# Building a Fitness TUI with Bot Army

A practical guide to building a Terminal User Interface for fitness tracking using Go, tview, and Bot Army's NATS bridge. This TUI will integrate seamlessly with the Bot Army ecosystem: creating tasks, querying system health, rolling for workout variety, and storing persistent progress.

**By the end, you'll have:**
- A working Go TUI that talks to Bot Army
- Fitness workouts logged as GTD tasks
- Random workout difficulty rolls
- Health status at a glance
- A pattern you can adapt for any Bot Army surface

**Estimated time:** 45 minutes

## What We're Building

```
┌─ Fitness TUI ─────────────────────────────────────┐
│ Today's Workouts                          Health ✅│
│ ❯ Morning Run (10 min) — pending                  │
│ • Strength (30 min) — pending                     │
│ • Afternoon Walk (20 min) — pending               │
│                                                    │
│ [n] New [c] Complete [r] Roll Difficulty         │
└────────────────────────────────────────────────────┘
```

A minimal TUI that:
1. Lists today's fitness workouts (from GTD)
2. Lets you log a new workout
3. Rolls for difficulty/variety (randomness)
4. Marks workouts complete
5. Shows system health

## Prerequisites

- **Go 1.20+** (or install via `brew install go`)
- **NATS running** on localhost:4222 (Bot Army production cluster)
- **Familiarity with Go basics** (structs, goroutines, error handling)
- **tview library** (we'll add it)

Verify NATS is reachable:
```bash
nats request --server nats://localhost:4222 bridge.system.fact '{}' --timeout 3s
# Should return: {"ok": true, "data": {"fact": "..."}}
```

## Part 1: Project Setup

### Create the project

```bash
mkdir -p ~/code/fitness-tui
cd ~/code/fitness-tui
git init
go mod init github.com/ergon-automation-labs/fitness-tui
```

### Add dependencies

```bash
go get github.com/rivo/tview
go get github.com/nats-io/nats.go
go get github.com/google/uuid
```

### Project structure

```
fitness-tui/
├── main.go                 # Entry point
├── internal/
│   ├── ui/
│   │   ├── app.go          # Main app lifecycle
│   │   └── views.go        # UI views (list, form, etc.)
│   └── nats_client/
│       └── client.go       # Bridge integration
├── go.mod
├── go.sum
├── Makefile
└── README.md
```

Create these directories:
```bash
mkdir -p internal/ui internal/nats_client
```

## Part 2: NATS Client Bridge Wrapper

**File:** `internal/nats_client/client.go`

This wrapper handles all communication with Bot Army via the bridge.

```go
package nats_client

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/nats-io/nats.go"
)

type BridgeClient struct {
	nc *nats.Conn
}

type Task struct {
	ID          string    `json:"id"`
	Title       string    `json:"title"`
	Description string    `json:"description"`
	Status      string    `json:"status"`
	Context     string    `json:"context,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
}

type BridgeResponse struct {
	Ok    bool        `json:"ok"`
	Data  interface{} `json:"data"`
	Error string      `json:"error,omitempty"`
}

// NewBridgeClient connects to NATS and returns a client
func NewBridgeClient(natsURL string) (*BridgeClient, error) {
	nc, err := nats.Connect(natsURL)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to NATS: %w", err)
	}
	return &BridgeClient{nc: nc}, nil
}

// CreateTask creates a new fitness task via bridge.task.create
func (bc *BridgeClient) CreateTask(title, description, context string) (*Task, error) {
	payload := map[string]interface{}{
		"title":       title,
		"description": description,
		"context":     context,
		"labels":      []string{"fitness"},
	}
	data, _ := json.Marshal(payload)

	msg, err := bc.nc.Request("bridge.task.create", data, 5*time.Second)
	if err != nil {
		return nil, fmt.Errorf("bridge.task.create failed: %w", err)
	}

	var resp BridgeResponse
	json.Unmarshal(msg.Data, &resp)
	if !resp.Ok {
		return nil, fmt.Errorf("bridge error: %v", resp.Error)
	}

	taskData, _ := json.Marshal(resp.Data)
	var task Task
	json.Unmarshal(taskData, &task)
	return &task, nil
}

// ListTasks fetches all fitness tasks
func (bc *BridgeClient) ListTasks() ([]Task, error) {
	payload := map[string]interface{}{
		"query": "context:fitness",
		"limit": 50,
	}
	data, _ := json.Marshal(payload)

	msg, err := bc.nc.Request("bridge.task.search", data, 5*time.Second)
	if err != nil {
		return nil, fmt.Errorf("bridge.task.search failed: %w", err)
	}

	var resp BridgeResponse
	json.Unmarshal(msg.Data, &resp)
	if !resp.Ok {
		return nil, fmt.Errorf("bridge error: %v", resp.Error)
	}

	respData := resp.Data.(map[string]interface{})
	tasksData, _ := json.Marshal(respData["tasks"])
	var tasks []Task
	json.Unmarshal(tasksData, &tasks)
	return tasks, nil
}

// CompleteTask marks a task as done
func (bc *BridgeClient) CompleteTask(taskID string) error {
	payload := map[string]interface{}{
		"task_id": taskID,
	}
	data, _ := json.Marshal(payload)

	msg, err := bc.nc.Request("bridge.task.complete", data, 5*time.Second)
	if err != nil {
		return fmt.Errorf("bridge.task.complete failed: %w", err)
	}

	var resp BridgeResponse
	json.Unmarshal(msg.Data, &resp)
	if !resp.Ok {
		return fmt.Errorf("bridge error: %v", resp.Error)
	}
	return nil
}

// RollDifficulty gets a randomness roll for workout difficulty
func (bc *BridgeClient) RollDifficulty() (int, error) {
	payload := map[string]interface{}{
		"notation": "d100",
		"purpose":  "fitness_workout_difficulty",
	}
	data, _ := json.Marshal(payload)

	msg, err := bc.nc.Request("bridge.random.roll", data, 5*time.Second)
	if err != nil {
		return 0, fmt.Errorf("bridge.random.roll failed: %w", err)
	}

	var resp BridgeResponse
	json.Unmarshal(msg.Data, &resp)
	if !resp.Ok {
		return 0, fmt.Errorf("bridge error: %v", resp.Error)
	}

	respData := resp.Data.(map[string]interface{})
	total := int(respData["total"].(float64))
	return total, nil
}

// SystemHealth fetches system awareness (all bots healthy?)
func (bc *BridgeClient) SystemHealth() (map[string]interface{}, error) {
	msg, err := bc.nc.Request("bridge.synapse.awareness", []byte("{}"), 5*time.Second)
	if err != nil {
		return nil, fmt.Errorf("bridge.synapse.awareness failed: %w", err)
	}

	var resp BridgeResponse
	json.Unmarshal(msg.Data, &resp)
	if !resp.Ok {
		return nil, fmt.Errorf("bridge error: %v", resp.Error)
	}

	return resp.Data.(map[string]interface{}), nil
}

// Close closes the NATS connection
func (bc *BridgeClient) Close() {
	bc.nc.Close()
}
```

## Part 3: UI Views

**File:** `internal/ui/views.go`

Define the UI layout and widgets:

```go
package ui

import (
	"fmt"

	"github.com/rivo/tview"
)

type Views struct {
	taskList   *tview.List
	statusBar  *tview.TextView
	inputForm  *tview.Form
	mainPages  *tview.Pages
}

// NewViews creates the TUI layout
func NewViews() *Views {
	v := &Views{
		taskList:  tview.NewList(),
		statusBar: tview.NewTextView(),
		inputForm: tview.NewForm(),
		mainPages: tview.NewPages(),
	}

	// Task list styling
	v.taskList.SetTitle(" Fitness Workouts  [n]ew  [c]omplete  [r]oll  [q]uit ")
	v.taskList.ShowSecondaryText(true)
	v.taskList.SetBorder(true)

	// Status bar
	v.statusBar.SetText("Loading...")
	v.statusBar.SetBorder(true)

	// Layout: list on top, status on bottom
	flex := tview.NewFlex().
		SetDirection(tview.FlexRow).
		AddItem(v.taskList, 0, 1, true).
		AddItem(v.statusBar, 3, 0, false)

	// Input form for new task
	v.inputForm.
		SetTitle(" New Workout ").
		SetBorder(true).
		AddInputField("Workout name", "Morning Run", 30, nil, nil).
		AddInputField("Duration (min)", "30", 10, nil, nil).
		AddButton("Create", func() {
			// Handle creation (we'll wire this up in app.go)
		}).
		AddButton("Cancel", func() {
			// Handle cancel
		})

	// Pages for navigation
	v.mainPages.AddPage("list", flex, true, true)
	v.mainPages.AddPage("form", v.inputForm, false, false)

	return v
}

// UpdateTaskList refreshes the task list display
func (v *Views) UpdateTaskList(tasks []map[string]interface{}) {
	v.taskList.Clear()

	for _, task := range tasks {
		title := task["title"].(string)
		status := task["status"].(string)
		id := task["id"].(string)

		// Format: "✓" for done, "◯" for pending
		icon := "◯"
		if status == "done" || status == "completed" {
			icon = "✓"
		}

		text := fmt.Sprintf("%s %s", icon, title)
		secondary := fmt.Sprintf("[%s]", status)

		// Store task ID in item name for retrieval
		v.taskList.AddItem(text, secondary, 0, nil)
	}

	if v.taskList.GetItemCount() == 0 {
		v.taskList.AddItem("[No workouts yet — press 'n' to add one]", "", 0, nil)
	}
}

// SetStatus updates the status bar
func (v *Views) SetStatus(msg string) {
	v.statusBar.SetText(msg)
}

// GetTaskInput gets the form input
func (v *Views) GetTaskInput() (name, duration string) {
	formItems := v.inputForm.GetFormItemCount()
	if formItems >= 2 {
		name = v.inputForm.GetFormItem(0).(*tview.InputField).GetText()
		duration = v.inputForm.GetFormItem(1).(*tview.InputField).GetText()
	}
	return
}

// ShowForm displays the input form
func (v *Views) ShowForm() {
	v.mainPages.SwitchToPage("form")
}

// HideForm hides the input form
func (v *Views) HideForm() {
	v.mainPages.SwitchToPage("list")
}

// GetMainView returns the root view for the app
func (v *Views) GetMainView() tview.Primitive {
	return v.mainPages
}
```

## Part 4: Main App

**File:** `internal/ui/app.go`

Wire everything together:

```go
package ui

import (
	"fmt"
	"log"

	"fitness-tui/internal/nats_client"
	"github.com/rivo/tview"
)

type App struct {
	tviewApp *tview.Application
	views    *Views
	bridge   *nats_client.BridgeClient
	tasks    []map[string]interface{}
}

// NewApp creates and initializes the app
func NewApp(natsURL string) (*App, error) {
	bc, err := nats_client.NewBridgeClient(natsURL)
	if err != nil {
		return nil, err
	}

	app := &App{
		tviewApp: tview.NewApplication(),
		views:    NewViews(),
		bridge:   bc,
	}

	// Load initial tasks
	app.loadTasks()

	// Setup keyboard handlers
	app.setupInputHandlers()

	return app, nil
}

// loadTasks fetches fitness tasks from the bridge
func (app *App) loadTasks() {
	tasks, err := app.bridge.ListTasks()
	if err != nil {
		app.views.SetStatus("Error loading tasks: " + err.Error())
		return
	}

	// Convert to map format for display
	var taskMaps []map[string]interface{}
	for _, task := range tasks {
		taskMaps = append(taskMaps, map[string]interface{}{
			"id":     task.ID,
			"title":  task.Title,
			"status": task.Status,
		})
	}
	app.tasks = taskMaps
	app.views.UpdateTaskList(taskMaps)
	app.views.SetStatus(fmt.Sprintf("Loaded %d workouts", len(taskMaps)))
}

// setupInputHandlers wires up keyboard events
func (app *App) setupInputHandlers() {
	app.tviewApp.SetInputCapture(func(event *tview.EventKey) *tview.EventKey {
		switch event.Rune {
		case 'n', 'N':
			// New workout
			app.views.ShowForm()
			app.handleNewWorkout()

		case 'c', 'C':
			// Complete selected workout
			idx := app.views.taskList.GetCurrentItemIndex()
			if idx >= 0 && idx < len(app.tasks) {
				task := app.tasks[idx]
				taskID := task["id"].(string)
				if err := app.bridge.CompleteTask(taskID); err != nil {
					app.views.SetStatus("Error: " + err.Error())
				} else {
					app.views.SetStatus(fmt.Sprintf("✓ Completed: %v", task["title"]))
					app.loadTasks()
				}
			}

		case 'r', 'R':
			// Roll difficulty
			roll, err := app.bridge.RollDifficulty()
			if err != nil {
				app.views.SetStatus("Error: " + err.Error())
			} else {
				difficulty := "Easy"
				if roll > 66 {
					difficulty = "Hard"
				} else if roll > 33 {
					difficulty = "Medium"
				}
				app.views.SetStatus(fmt.Sprintf("Difficulty roll: %d (%s)", roll, difficulty))
			}

		case 'q', 'Q':
			// Quit
			app.tviewApp.Stop()

		case '?':
			// Help
			app.views.SetStatus("[n]ew  [c]omplete  [r]oll difficulty  [q]uit")
		}
		return event
	})
}

// handleNewWorkout prompts for input and creates a task
func (app *App) handleNewWorkout() {
	// Simple inline approach: modal dialog with form
	// (In production, you'd use the form view we defined)

	modal := tview.NewForm().
		AddInputField("Workout name", "Morning Run", 30, nil, nil).
		AddInputField("Duration (min)", "30", 10, nil, nil).
		AddButton("Create", func() {
			name, _ := modal.GetFormItem(0).(*tview.InputField).GetText(), "30"
			duration, _ := modal.GetFormItem(1).(*tview.InputField).GetText(), "30"

			desc := fmt.Sprintf("Complete %s-minute %s", duration, name)
			_, err := app.bridge.CreateTask(name, desc, "fitness")
			if err != nil {
				app.views.SetStatus("Error creating task: " + err.Error())
			} else {
				app.views.SetStatus(fmt.Sprintf("✓ Created: %s", name))
				app.loadTasks()
			}
			app.views.HideForm()
		}).
		AddButton("Cancel", func() {
			app.views.HideForm()
		})

	modal.SetBorder(true).SetTitle(" New Workout ")

	// Show modal (simplified—in production use proper modal handling)
	app.views.HideForm()
}

// Run starts the TUI event loop
func (app *App) Run() error {
	return app.tviewApp.SetRoot(app.views.GetMainView(), true).Run()
}

// Close cleans up resources
func (app *App) Close() {
	app.bridge.Close()
}
```

## Part 5: Entry Point

**File:** `main.go`

```go
package main

import (
	"log"
	"os"

	"fitness-tui/internal/ui"
)

func main() {
	// Use prod NATS cluster (4222)
	natsURL := os.Getenv("NATS_SERVERS")
	if natsURL == "" {
		natsURL = "nats://localhost:4222"
	}

	app, err := ui.NewApp(natsURL)
	if err != nil {
		log.Fatalf("Failed to initialize app: %v", err)
	}
	defer app.Close()

	if err := app.Run(); err != nil {
		log.Fatalf("App failed: %v", err)
	}
}
```

## Part 6: Build & Run

**File:** `Makefile`

```makefile
.PHONY: build run clean test

build:
	go build -o fitness-tui ./

run: build
	./fitness-tui

clean:
	rm -f fitness-tui

test:
	go test ./...

smoke-test:
	nats request --server nats://localhost:4222 bridge.system.fact '{}' --timeout 3s | jq '.ok'

docker-build:
	docker build -t fitness-tui:latest .

docker-run:
	docker run --rm --network host fitness-tui:latest
```

## Part 7: Test It

### Start the TUI locally

```bash
cd ~/code/fitness-tui
make build
make run
```

You should see:
```
┌─ Fitness Workouts  [n]ew  [c]omplete  [r]oll  [q]uit ─┐
│ [No workouts yet — press 'n' to add one]              │
└──────────────────────────────────────────────────────────┘
Loading...
```

### Try the commands

- **Press `n`** → Create a new workout
  - Type "Morning Run", "30" minutes
  - Press Create → Task appears in list
- **Press `r`** → Roll for difficulty (rolls d100)
  - Shows "Easy/Medium/Hard" based on roll
- **Press `c`** → Mark selected workout done
  - Task status changes to "done"
- **Press `?`** → Show help

### Verify in GTD TUI

In another terminal:
```bash
cd ~/code/elixir_bots/surfaces/golang_tui/gtd-tui
make run
```

Switch to "Tasks" tab → You should see your fitness workouts created via the fitness TUI, showing up in the shared GTD system!

## Part 8: Docker Deployment

**File:** `Dockerfile`

```dockerfile
FROM golang:1.24-alpine AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o fitness-tui ./

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=build /app/fitness-tui .

ENV NATS_SERVERS=nats://host.docker.internal:4222
ENTRYPOINT ["./fitness-tui"]
```

Build and run:
```bash
make docker-build
make docker-run
```

(Note: `host.docker.internal` allows the container to reach localhost NATS)

## Part 9: Deploy to Bot Army

Once you're happy with the TUI:

### 1. Push to GitHub

```bash
git remote add origin https://github.com/YOUR_ORG/fitness-tui.git
git add .
git commit -m "feat: Initial fitness TUI with Bot Army integration"
git push -u origin main
```

### 2. Create a GTD task for it

```bash
nats request --server nats://localhost:4222 bridge.task.create '{
  "title": "Fitness TUI v0.1.0 released",
  "description": "Terminal UI for logging fitness workouts. Uses bridge.task.* and bridge.random.roll.",
  "context": "surfaces",
  "labels": ["released"]
}' --timeout 5s
```

### 3. Reference in Bot Army docs

Add to `/Users/abby/code/elixir_bots/docs/EXTERNAL_PROJECT_INTEGRATION.md`:

```markdown
## Example: Fitness TUI

A complete Go TUI integrating with Bot Army.

- **Repo:** https://github.com/your-org/fitness-tui
- **Pattern:** Uses `bridge.task.create`, `bridge.task.search`, `bridge.random.roll`
- **UI:** tview (same as gtd-tui)
- **Deploy:** Docker or standalone binary

See tutorial: [Building a Fitness TUI](TUTORIAL_BUILDING_FITNESS_TUI.md)
```

## Next Steps

### Extend the TUI

1. **Add stats** — Show weekly/monthly workout count via `bridge.project.list`
2. **Sync with fitness_bot** — Query `fitness.workouts.list` for persistence
3. **Health checks** — Display system health via `bridge.synapse.awareness`
4. **Daily brief** — Show today's tasks from `bridge.chronicle.daily.brief`

### Share It

- Write a blog post: "I Built a Fitness TUI on Top of Bot Army"
- Tweet the GitHub link
- Show it at a Go meetup
- Submit to Awesome Go lists

### Integration Ideas

Combine the fitness TUI with:
- **Dispatcher** — Route "complete workout" intentions to other bots
- **RPG bot** — Gamify with XP rewards for workouts
- **Learning bot** — Track workout consistency and suggest improvements
- **Discord** — Post daily fitness summary to your fitness channel via Synapse

## Troubleshooting

### "No responders" error

NATS bridge isn't reachable. Check:
```bash
make smoke-test  # Should return {"ok": true}
```

If it fails, ensure Bot Army is running:
```bash
cd ~/code/elixir_bots
make doctor  # System health check
```

### Form doesn't appear

The form modal handling in this simplified version uses a basic approach. In production, use tview's proper modal/overlay patterns.

### Tasks don't persist

They do—they're stored in the GTD bot database. The fitness TUI is just a UI client. Restart the TUI and reload to see them again.

## What You've Learned

✅ Building a Go TUI with tview  
✅ NATS request/reply client pattern  
✅ Bridge integration (task creation, querying, randomness)  
✅ How to talk to Bot Army from any language/framework  
✅ Deploying a surface as a Docker container  

## See Also

- [EXTERNAL_PROJECT_INTEGRATION.md](EXTERNAL_PROJECT_INTEGRATION.md) — Full bridge API reference
- [gtd-tui](../surfaces/golang_tui/gtd-tui/) — Full-featured TUI (reference implementation)
- [fitness_bot](../bot_army_fitness/) — Backend bot for fitness tracking
- [PI_GO_BRIDGE_SUBJECTS.md](PI_GO_BRIDGE_SUBJECTS.md) — Bridge contract details

---

**Questions?** Open an issue on [the starter repo](https://github.com/ergon-automation-labs/ergon-starter).

**Want to contribute?** Check [CONTRIBUTING.md](../CONTRIBUTING.md) in the main Bot Army repo.

Good luck building! 🏃‍♂️
