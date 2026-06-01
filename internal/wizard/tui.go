package wizard

import (
	"fmt"

	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"
)

// WizardTUI manages the interactive setup flow with tview.
type WizardTUI struct {
	app    *tview.Application
	cfg    *Config
	result error

	// Layout components
	header    *tview.TextView
	status    *tview.TextView
	contentFx *tview.Flex // flexbox that holds the current step widget
	root      *tview.Flex

	// Navigation state
	currentStep int
}

// NewWizardTUI creates a new wizard UI.
func NewWizardTUI(cfg *Config) *WizardTUI {
	return &WizardTUI{
		app: tview.NewApplication(),
		cfg: cfg,
	}
}

// Run executes the wizard steps and returns any error (cancelled, validation failure).
func (w *WizardTUI) Run() error {
	w.buildLayout()

	// Run through steps synchronously
	if err := w.stepSelectPack(); err != nil {
		return err
	}
	if err := w.stepSelectBots(); err != nil {
		return err
	}
	if err := w.stepConfigurePorts(); err != nil {
		return err
	}
	// GitHub setup (conditional: only if github_bot is in selected packs)
	if w.hasGitHub() {
		if err := w.stepConfigureGitHub(); err != nil {
			return err
		}
	}
	if err := w.stepSelectProviders(); err != nil {
		return err
	}
	if err := w.stepConfigureEnvVars(); err != nil {
		return err
	}
	// Terminal context helper (optional)
	if err := w.stepConfigureTerminalContext(); err != nil {
		return err
	}
	if err := w.stepReviewAndConfirm(); err != nil {
		return err
	}

	return nil
}

// buildLayout creates the root layout: header, content area, status bar.
func (w *WizardTUI) buildLayout() {
	// Header
	w.header = tview.NewTextView()
	w.header.SetDynamicColors(true)
	w.setHeader("Bot Army Starter")

	// Status bar
	w.status = tview.NewTextView()
	w.status.SetDynamicColors(true)
	w.setStatus("")

	// Content area (will be swapped per step)
	w.contentFx = tview.NewFlex().SetDirection(tview.FlexRow)

	// Root layout
	w.root = tview.NewFlex().SetDirection(tview.FlexRow).
		AddItem(w.header, 1, 0, false).
		AddItem(w.contentFx, 0, 1, true).
		AddItem(w.status, 1, 0, false)

	w.app.SetRoot(w.root, true)
}

// stepSelectPack runs Step 1: select starter pack (multi-select list).
func (w *WizardTUI) stepSelectPack() error {
	// Load packs
	packs, err := LoadPacks()
	if err != nil {
		return err
	}

	list := tview.NewList()
	list.SetBorder(true).
		SetTitle(" Select a Starter Pack  ↑↓:nav  Space:toggle  s:skip  Enter:next ").
		SetTitleAlign(tview.AlignLeft)

	// Track selection
	selected := make(map[int]bool)

	// Render the list
	redraw := func() {
		list.Clear()
		for i, p := range packs {
			var prefix string
			if selected[i] {
				prefix = "[green][✓][-] "
			} else {
				prefix = "[ ] "
			}
			botList := ""
			for j, name := range p.Bots {
				if j > 0 {
					botList += " · "
				}
				botList += name
			}
			list.AddItem(prefix+p.Name, p.Description+" ("+botList+")", 0, nil)
		}
		// Add Custom option
		list.AddItem("[ ] Custom", "I'll pick bots manually", 0, nil)
	}
	redraw()

	var done bool
	list.SetInputCapture(func(ev *tcell.EventKey) *tcell.EventKey {
		i := list.GetCurrentItem()
		if i < 0 {
			return ev
		}

		switch ev.Rune() {
		case ' ', 'x':
			// Toggle selection
			selected[i] = !selected[i]
			redraw()
			list.SetCurrentItem(i)
			return nil

		case 's':
			// Skip pack selection (custom mode)
			w.cfg.SelectedPacks = []Pack{}
			done = true
			w.app.Stop()
			return nil

		case 'q':
			return tcell.NewEventKey(tcell.KeyCtrlC, 'q', tcell.ModCtrl)

		default:
			switch ev.Key() {
			case tcell.KeyEnter:
				// Collect selected packs
				var result []Pack
				for i, p := range packs {
					if selected[i] {
						result = append(result, p)
					}
				}
				w.cfg.SelectedPacks = result

				// Check if Development pack was selected
				for _, pack := range result {
					if pack.Name == "development" {
						w.cfg.DevMode = true
						break
					}
				}

				done = true
				w.app.Stop()
				return nil

			case tcell.KeyEscape:
				w.result = fmt.Errorf("cancelled")
				w.app.Stop()
				return nil
			}
		}
		return ev
	})

	w.setContent(list, 1, "↑↓:nav  Space:toggle  s:skip  Enter:next  Esc:cancel  q:quit")

	if err := w.app.Run(); err != nil {
		return err
	}

	if w.result != nil {
		return w.result
	}
	if !done {
		return fmt.Errorf("step 1 cancelled")
	}

	return nil
}

// setHeader updates the header text with step indicator.
func (w *WizardTUI) setHeader(title string) {
	stepIndicator := ""
	if w.currentStep > 0 && w.currentStep <= 6 {
		steps := []rune{'●', '●', '●', '●', '●', '●'}
		for i := w.currentStep; i < 6; i++ {
			steps[i] = '○'
		}
		stepIndicator = fmt.Sprintf("  %s  Step %d/6", string(steps), w.currentStep)
	}
	text := fmt.Sprintf("Bot Army Starter%s", stepIndicator)
	w.header.SetText(text)
}

// setStatus updates the status bar text with key hints.
func (w *WizardTUI) setStatus(hints string) {
	if hints != "" {
		w.status.SetText(hints)
	}
}

// setContent replaces the current step content and updates header/status.
func (w *WizardTUI) setContent(widget tview.Primitive, step int, hints string) {
	w.currentStep = step
	w.contentFx.Clear()
	w.contentFx.AddItem(widget, 0, 1, true)
	w.setHeader("Bot Army Starter")
	w.setStatus(hints)
	w.app.SetFocus(widget)
}

// stepSelectBots runs Step 2: select bots (multi-select list).
func (w *WizardTUI) stepSelectBots() error {
	w.currentStep = 2

	// Load packs to show pack membership labels
	packs, _ := LoadPacks()
	botPackMap := BotPackMap(packs)

	list := tview.NewList()
	list.SetBorder(true).
		SetTitle(" Select Bots  ↑↓:nav  Space:toggle  Enter:next ").
		SetTitleAlign(tview.AlignLeft)

	// Track selection: core bots locked on, pack-selected bots on, others deselected
	selected := make(map[int]bool)
	for i, b := range w.cfg.AllBots {
		if b.IsCore() {
			selected[i] = true
		}
	}
	// Pre-select bots from selected packs
	for _, pack := range w.cfg.SelectedPacks {
		for _, botName := range pack.Bots {
			for i, b := range w.cfg.AllBots {
				if b.Name == botName {
					selected[i] = true
				}
			}
		}
	}

	// Render the list
	redraw := func() {
		list.Clear()
		for i, b := range w.cfg.AllBots {
			var prefix string
			if b.IsCore() {
				prefix = "[gray][✓][-] (required) "
			} else if selected[i] {
				prefix = "[green][✓][-] "
			} else {
				prefix = "[ ] "
			}
			// Add pack label
			packName := botPackMap[b.Name]
			var packLabel string
			if packName != "" {
				packLabel = " [dim][" + packName + "][-]"
			}
			list.AddItem(prefix+b.Name+packLabel, b.App, 0, nil)
		}
	}
	redraw()

	var done bool
	list.SetInputCapture(func(ev *tcell.EventKey) *tcell.EventKey {
		i := list.GetCurrentItem()
		if i < 0 {
			return ev
		}

		switch ev.Rune() {
		case ' ', 'x':
			// Toggle selection (unless core)
			if !w.cfg.AllBots[i].IsCore() {
				selected[i] = !selected[i]
				redraw()
				list.SetCurrentItem(i)
			}
			return nil

		case 'q':
			return tcell.NewEventKey(tcell.KeyCtrlC, 'q', tcell.ModCtrl)

		default:
			switch ev.Key() {
			case tcell.KeyEnter:
				// Collect selected bots
				var result []Bot
				for i, b := range w.cfg.AllBots {
					if selected[i] {
						result = append(result, b)
					}
				}
				w.cfg.SelectedBots = result
				done = true
				w.app.Stop()
				return nil

			case tcell.KeyEscape:
				w.result = fmt.Errorf("cancelled")
				w.app.Stop()
				return nil
			}
		}
		return ev
	})

	w.setContent(list, 2, "↑↓:nav  Space:toggle  Enter:next  Esc:cancel  q:quit")

	// Run the app until this step completes
	if err := w.app.Run(); err != nil {
		return err
	}

	if w.result != nil {
		return w.result
	}
	if !done {
		return fmt.Errorf("step 2 cancelled")
	}

	return nil
}

// stepConfigurePorts runs Step 3: configure host ports (form).
func (w *WizardTUI) stepConfigurePorts() error {
	w.currentStep = 3

	form := tview.NewForm()
	form.SetBorder(true).
		SetTitle(" Configure Ports  Enter:save  Esc:cancel ").
		SetTitleAlign(tview.AlignLeft)

	form.AddInputField("NATS port", w.cfg.Ports.NATS, 10, nil, nil)
	form.AddInputField("NATS monitor port", w.cfg.Ports.NATSMonitor, 10, nil, nil)
	form.AddInputField("PostgreSQL port", w.cfg.Ports.Postgres, 10, nil, nil)
	form.AddInputField("Ollama port", w.cfg.Ports.Ollama, 10, nil, nil)
	form.AddInputField("MCP server port", w.cfg.Ports.MCP, 10, nil, nil)
	form.AddInputField("Docker registry port", w.cfg.Ports.Registry, 10, nil, nil)

	form.AddButton("Next", func() {
		w.cfg.Ports.NATS = form.GetFormItem(0).(*tview.InputField).GetText()
		w.cfg.Ports.NATSMonitor = form.GetFormItem(1).(*tview.InputField).GetText()
		w.cfg.Ports.Postgres = form.GetFormItem(2).(*tview.InputField).GetText()
		w.cfg.Ports.Ollama = form.GetFormItem(3).(*tview.InputField).GetText()
		w.cfg.Ports.MCP = form.GetFormItem(4).(*tview.InputField).GetText()
		w.cfg.Ports.Registry = form.GetFormItem(5).(*tview.InputField).GetText()
		w.app.Stop()
	})

	form.AddButton("Cancel", func() {
		w.result = fmt.Errorf("cancelled")
		w.app.Stop()
	})

	w.setContent(form, 3, "Enter:save  Esc:cancel")

	if err := w.app.Run(); err != nil {
		return err
	}

	if w.result != nil {
		return w.result
	}

	return nil
}

// hasGitHub checks if any selected pack contains the github_bot
func (w *WizardTUI) hasGitHub() bool {
	for _, pack := range w.cfg.SelectedPacks {
		for _, botName := range pack.Bots {
			if botName == "github" {
				return true
			}
		}
	}
	return false
}

// stepConfigureGitHub runs GitHub webhook setup (conditional, only if github_bot is selected)
func (w *WizardTUI) stepConfigureGitHub() error {
	w.currentStep = 4

	form := tview.NewForm()
	form.SetBorder(true).
		SetTitle(" Configure GitHub Webhook  Enter:save  Esc:skip ").
		SetTitleAlign(tview.AlignLeft)

	form.AddInputField("GitHub Token (ghp_...)", w.cfg.GitHubToken, 50, nil, nil)
	form.AddInputField("Webhook Secret (min 8 chars)", w.cfg.GitHubWebhookSecret, 50, nil, nil)

	form.AddButton("Save & Continue", func() {
		w.cfg.GitHubToken = form.GetFormItem(0).(*tview.InputField).GetText()
		w.cfg.GitHubWebhookSecret = form.GetFormItem(1).(*tview.InputField).GetText()
		w.app.Stop()
	})

	form.AddButton("Skip", func() {
		// Clear GitHub config if user skips
		w.cfg.GitHubToken = ""
		w.cfg.GitHubWebhookSecret = ""
		w.app.Stop()
	})

	w.setContent(form, 4, "Enter:save  Esc:skip  GitHub webhook is optional")

	if err := w.app.Run(); err != nil {
		return err
	}

	if w.result != nil {
		return w.result
	}

	return nil
}

// stepSelectProviders runs Step 5: select LLM providers (multi-select list).
func (w *WizardTUI) stepSelectProviders() error {
	w.currentStep = 4

	list := tview.NewList()
	list.SetBorder(true).
		SetTitle(" Select LLM Providers  ↑↓:nav  Space:toggle  Enter:next ").
		SetTitleAlign(tview.AlignLeft)

	// Track selection
	selected := make(map[int]bool)

	// Render the list
	redraw := func() {
		list.Clear()
		for i, p := range Providers {
			var prefix string
			if selected[i] {
				prefix = "[green][✓][-] "
			} else {
				prefix = "[ ] "
			}
			list.AddItem(prefix+p.Label, p.Name, 0, nil)
		}
	}
	redraw()

	var done bool
	list.SetInputCapture(func(ev *tcell.EventKey) *tcell.EventKey {
		i := list.GetCurrentItem()
		if i < 0 {
			return ev
		}

		switch ev.Rune() {
		case ' ', 'x':
			selected[i] = !selected[i]
			redraw()
			list.SetCurrentItem(i)
			return nil

		case 'q':
			return tcell.NewEventKey(tcell.KeyCtrlC, 'q', tcell.ModCtrl)

		default:
			switch ev.Key() {
			case tcell.KeyEnter:
				// Validate at least one selected
				if len(selected) == 0 {
					// No selection — show error in status bar and don't advance
					w.setStatus("[red]At least one provider required[-]")
					return nil
				}
				// Collect selected providers
				var result []Provider
				for i, p := range Providers {
					if selected[i] {
						result = append(result, p)
					}
				}
				w.cfg.SelectedProviders = result
				done = true
				w.app.Stop()
				return nil

			case tcell.KeyEscape:
				w.result = fmt.Errorf("cancelled")
				w.app.Stop()
				return nil
			}
		}
		return ev
	})

	w.setContent(list, 4, "↑↓:nav  Space:toggle  Enter:next  Esc:cancel  q:quit")

	if err := w.app.Run(); err != nil {
		return err
	}

	if w.result != nil {
		return w.result
	}
	if !done {
		return fmt.Errorf("step 4 cancelled")
	}

	return nil
}

// stepConfigureEnvVars runs Step 5: configure environment variables (form).
func (w *WizardTUI) stepConfigureEnvVars() error {
	w.currentStep = 5

	form := tview.NewForm()
	form.SetBorder(true).
		SetTitle(" Configure Environment Variables  Enter:save  Esc:cancel ").
		SetTitleAlign(tview.AlignLeft)

	// Collect all env vars from selected providers and bots
	fieldMap := make(map[int]EnvVar) // field index → EnvVar
	fieldIdx := 0

	for _, p := range w.cfg.SelectedProviders {
		form.AddTextView("", "[yellow]"+p.Label+"[-]", 0, 1, true, false)
		fieldIdx++

		for _, ev := range p.EnvVars {
			val := w.cfg.EnvValues[ev.Key]
			if val == "" {
				val = ev.Default
			}

			if ev.Secret {
				form.AddPasswordField(ev.Key, val, 40, '*', nil)
			} else {
				form.AddInputField(ev.Key, val, 40, nil, nil)
			}

			fieldMap[fieldIdx] = ev
			fieldIdx++
		}
	}

	for _, bot := range w.cfg.SelectedBots {
		if len(bot.EnvVars) == 0 {
			continue
		}

		form.AddTextView("", "[yellow]"+bot.Name+"[-]", 0, 1, true, false)
		fieldIdx++

		for _, ev := range bot.EnvVars {
			val := w.cfg.EnvValues[ev.Key]
			if val == "" {
				val = ev.Default
			}

			if ev.Secret {
				form.AddPasswordField(ev.Key, val, 40, '*', nil)
			} else {
				form.AddInputField(ev.Key, val, 40, nil, nil)
			}

			fieldMap[fieldIdx] = ev
			fieldIdx++
		}
	}

	form.AddButton("Next", func() {
		// Read all values back from form
		for idx, ev := range fieldMap {
			item := form.GetFormItem(idx)
			var val string
			if field, ok := item.(*tview.InputField); ok {
				val = field.GetText()
			}
			w.cfg.EnvValues[ev.Key] = val
		}
		w.app.Stop()
	})

	form.AddButton("Cancel", func() {
		w.result = fmt.Errorf("cancelled")
		w.app.Stop()
	})

	w.setContent(form, 5, "Enter:save  Esc:cancel")

	if err := w.app.Run(); err != nil {
		return err
	}

	if w.result != nil {
		return w.result
	}

	return nil
}

// stepConfigureTerminalContext runs Step 5.5: configure terminal context helper (optional).
func (w *WizardTUI) stepConfigureTerminalContext() error {
	w.currentStep = 5

	list := tview.NewList()
	list.SetBorder(true).
		SetTitle(" Terminal Context Helper  Space:select  Enter:next ").
		SetTitleAlign(tview.AlignLeft)

	// Track selection
	installed := w.cfg.TerminalContext

	// Render the list
	redraw := func() {
		list.Clear()
		if installed {
			list.AddItem("[green][●][-] Install bot-army-shell", "Enable context-aware prompts and Ghostty title automation", 0, nil)
		} else {
			list.AddItem("[ ][ ] Install bot-army-shell", "Enable context-aware prompts and Ghostty title automation", 0, nil)
		}
		list.AddItem("[gray][ ] Skip[-]", "Install only core bots", 0, nil)
	}
	redraw()

	var done bool
	list.SetInputCapture(func(ev *tcell.EventKey) *tcell.EventKey {
		i := list.GetCurrentItem()
		if i < 0 {
			return ev
		}

		switch ev.Rune() {
		case ' ', 'x':
			// Toggle selection
			if i == 0 {
				installed = !installed
				redraw()
				list.SetCurrentItem(i)
			}
			return nil

		case 'q':
			return tcell.NewEventKey(tcell.KeyCtrlC, 'q', tcell.ModCtrl)

		default:
			switch ev.Key() {
			case tcell.KeyEnter:
				w.cfg.TerminalContext = installed
				done = true
				w.app.Stop()
				return nil

			case tcell.KeyEscape:
				w.result = fmt.Errorf("cancelled")
				w.app.Stop()
				return nil
			}
		}
		return ev
	})

	w.setContent(list, 5, "Space:toggle  Enter:save  Esc:cancel")

	if err := w.app.Run(); err != nil {
		return err
	}

	if w.result != nil {
		return w.result
	}
	if !done {
		return fmt.Errorf("step 5.5 cancelled")
	}

	return nil
}

// stepReviewAndConfirm runs Step 6: review and confirm (text view).
func (w *WizardTUI) stepReviewAndConfirm() error {
	w.currentStep = 6

	// Build summary text
	summary := "[yellow]Bot Army Starter Configuration[-]\n\n"
	summary += "[cyan]Selected Bots[-]\n"
		for _, b := range w.cfg.SelectedBots {
			summary += "  • " + b.Name + " (v" + b.Version + ")\n"
			if b.InstallNote != "" {
				summary += "    [yellow]" + b.InstallNote + "[-]\n"
			}
		}
	summary += "\n[cyan]Host Ports[-]\n"
	summary += "  NATS: " + w.cfg.Ports.NATS + "\n"
	summary += "  PostgreSQL: " + w.cfg.Ports.Postgres + "\n"
	summary += "  Ollama: " + w.cfg.Ports.Ollama + "\n"
	summary += "  MCP server: " + w.cfg.Ports.MCP + "\n"
	summary += "  Docker registry: " + w.cfg.Ports.Registry + "\n"

	summary += "\n[cyan]LLM Providers[-]\n"
	for _, p := range w.cfg.SelectedProviders {
		summary += "  • " + p.Label + "\n"
	}

	summary += "\n[cyan]Build Your Own Bot[-]\n"
	summary += "A Bot Army bot is an Elixir/OTP GenServer app that subscribes to\n"
	summary += "NATS subjects and responds to messages from other bots and surfaces.\n\n"
	summary += "[cyan]Quick start (one command):[-]\n"
	summary += "  cd ~/code/elixir_bots/bot_template\n"
	summary += "  ./setup_new_bot.sh bot_army_mybot mybot_bot ergon-mybot\n\n"
	summary += "This scaffolds a full project with NATS consumer, health signals,\n"
	summary += "HTTP client, pre-push hooks, and Makefile targets.\n\n"
	summary += "[cyan]Add to your fleet:[-]\n"
	summary += "  ./bot-army add mybot\n"
	summary += "  docker compose up -d --build\n\n"
	summary += "[cyan]MCP Server (Claude Desktop Integration):[-]\n"
	summary += "Streamable HTTP transport — no local Elixir/OTP needed.\n"
	summary += "  1. Bot Army runs the MCP server in Docker on port " + w.cfg.Ports.MCP + "\n"
	summary += "  2. In Claude Desktop settings, add MCP server:\n"
	summary += "     \"mcpServers\": { \"bot-army\": { \"url\": \"http://localhost:" + w.cfg.Ports.MCP + "/mcp\" } }\n"
	summary += "  3. Restart Claude Desktop — Bot Army tools will appear.\n\n"
	summary += "[cyan]Reference:[-]\n"
	summary += "  bot_template/docs/BEST_PRACTICES.md\n"
	summary += "  bot_template/UPDATES.md\n\n"
	summary += "[green]Press Enter to start setup or Esc to go back[-]"

	review := tview.NewTextView()
	review.SetBorder(true).
		SetTitle(" Review Configuration  Enter:start  Esc:back ").
		SetTitleAlign(tview.AlignLeft)
	review.SetDynamicColors(true)
	review.SetText(summary)

	var confirmed bool
	review.SetInputCapture(func(ev *tcell.EventKey) *tcell.EventKey {
		switch ev.Key() {
		case tcell.KeyEnter:
			confirmed = true
			w.app.Stop()
			return nil
		case tcell.KeyEscape:
			w.app.Stop()
			return nil
		}
		return ev
	})

	w.setContent(review, 6, "Enter:start setup  Esc:back  q:quit")

	if err := w.app.Run(); err != nil {
		return err
	}

	if !confirmed {
		return fmt.Errorf("setup cancelled")
	}

	return nil
}
