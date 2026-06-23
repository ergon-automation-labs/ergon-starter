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
	if err := w.stepConfigureIntegrations(); err != nil {
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
	if err := w.stepConfigureVolumes(); err != nil {
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

	helpText := `[yellow]💡 What are Starter Packs?[-]
Packs are pre-configured bundles of bots with common integrations. All packs include required libraries and LLM proxy.

[dim]• Core[-]          GTD, Dispatcher, PARA, Bridge - the essential workflow system
[dim]• Social Media[-]  Core + Discord/Synapse bridge for chat platforms
[dim]• Learning[-]      Core + Research tools and learning management
[dim]• Areas[-]         Core + Area-specific bots (Fitness, Chore, RPG)
[dim]• Research[-]      Core + Job search and feed management tools
[dim]• Custom[-]        Skip packs and pick individual bots yourself (required libs always included)`

	w.setContent(list, 1, "↑↓:nav  Space:toggle  s:skip  Enter:next  Esc:cancel  q:quit", helpText)

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
func (w *WizardTUI) setContent(widget tview.Primitive, step int, hints string, helpTexts ...string) {
	w.currentStep = step
	w.contentFx.Clear()

	// If help text provided, create a flex layout with help above widget
	if len(helpTexts) > 0 && helpTexts[0] != "" {
		helpView := tview.NewTextView()
		helpView.SetDynamicColors(true)
		helpView.SetText(helpTexts[0])
		helpView.SetBorder(false)
		helpView.SetTextAlign(tview.AlignLeft)
		helpView.SetWordWrap(true)

		flex := tview.NewFlex().SetDirection(tview.FlexRow)
		flex.AddItem(helpView, 8, 0, false)
		flex.AddItem(tview.NewBox(), 1, 0, false)
		flex.AddItem(widget, 0, 1, true)

		w.contentFx.AddItem(flex, 0, 1, true)
	} else {
		w.contentFx.AddItem(widget, 0, 1, true)
	}

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
			desc := b.Description
			if desc == "" {
				desc = b.App
			}
			list.AddItem(prefix+b.Name+packLabel, desc, 0, nil)
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

	helpText := `[yellow]💡 About Bots[-]
Each bot is a specialized service that handles a specific function. You can customize your system by selecting the bots you need.

[dim]• Required bots[-]             Foundation libraries + LLM proxy (locked, can't be removed)
[dim]• Pack-included bots[-]        Auto-selected from your chosen pack(s) above
[dim]• Optional bots[-]             Toggle with Space to add/remove as needed
[dim]• Tip[-]                       Unselect pack bots you don't want, add experimental bots to explore`

	w.setContent(list, 2, "↑↓:nav  Space:toggle  Enter:next  Esc:cancel  q:quit", helpText)

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

// stepConfigureIntegrations runs Step 3: configure integrations based on selected bots.
func (w *WizardTUI) stepConfigureIntegrations() error {
	w.currentStep = 3

	// Determine required integrations based on selected bots
	required := DeterminedRequiredIntegrations(w.cfg.SelectedBots)
	w.cfg.EnabledIntegrations = required

	// Create a list showing which integrations will be enabled
	list := tview.NewList()
	list.SetBorder(true).
		SetTitle(" Integration Status  ↑↓:nav  Space:toggle  Enter:next ").
		SetTitleAlign(tview.AlignLeft)

	// Build list of integrations
	integrationOrder := []string{"BRIDGE", "LLM", "PARA", "CONTEXT", "NOTIFICATION", "SYNAPSE", "DISPATCHER", "GTD"}
	selected := make(map[int]bool)
	for _, integ := range integrationOrder {
		selected[len(selected)] = required[integ]
	}

	redraw := func() {
		list.Clear()
		for i, integ := range integrationOrder {
			var prefix string
			if integ == "GTD" {
				prefix = "[gray][✓][-] (required) "
			} else if selected[i] {
				prefix = "[green][✓][-] "
			} else {
				prefix = "[ ] "
			}
			desc := IntegrationDescriptions[integ]
			list.AddItem(prefix+integ, desc, 0, nil)
		}
	}
	redraw()

	var done bool
	list.SetInputCapture(func(ev *tcell.EventKey) *tcell.EventKey {
		i := list.GetCurrentItem()
		if i < 0 {
			return ev
		}

		if i < len(integrationOrder) && integrationOrder[i] != "GTD" {
			switch ev.Rune() {
			case ' ', 'x':
				selected[i] = !selected[i]
				w.cfg.EnabledIntegrations[integrationOrder[i]] = selected[i]
				redraw()
				list.SetCurrentItem(i)
				return nil
			}
		}

		switch ev.Key() {
		case tcell.KeyEnter:
			// Update config with selected integrations
			for i, integ := range integrationOrder {
				if integ != "GTD" {
					w.cfg.EnabledIntegrations[integ] = selected[i]
				}
			}
			done = true
			w.app.Stop()
			return nil
		case tcell.KeyEscape:
			w.app.Stop()
			return nil
		}
		return ev
	})

	helpText := `[yellow]💡 About Integrations[-]
Integrations enable features needed by certain bots. Disable unwanted integrations to reduce resource usage.

[dim]• Greyed items[-]      Required integrations (can't be changed)
[dim]• Green items[-]       Auto-enabled because you selected a bot that uses them
[dim]• Unchecked items[-]   Optional integrations (toggle with Space)
[dim]• Tip[-]               Each integration can be toggled independently to customize your system`

	w.setContent(list, 3, "↑↓:nav  Space:toggle  Enter:next  Esc:cancel", helpText)

	if err := w.app.Run(); err != nil {
		return err
	}
	if !done {
		return fmt.Errorf("step 3 cancelled")
	}

	return nil
}

// stepConfigurePorts runs Step 4: configure host ports (form).
func (w *WizardTUI) stepConfigurePorts() error {
	w.currentStep = 4

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

	helpText := `[yellow]💡 About Ports[-]
These TCP ports on your computer allow services to communicate. Change them only if you have port conflicts.

[dim]• NATS (4222)[-]          Message broker - enables bots to send messages to each other
[dim]• Postgres (5432)[-]      Database - persistent storage for bot state and data
[dim]• Ollama (11434)[-]       Local LLM server - only needed if self-hosting AI models
[dim]• MCP Server (39900)[-]   Claude Desktop integration - for using bots in Claude MCP
[dim]• Tip[-]                  If a port is already in use, pick a different one (e.g. 54222 instead of 4222)`

	w.setContent(form, 4, "Enter:save  Esc:cancel", helpText)

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
	w.currentStep = 5

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

	helpText := `[yellow]💡 GitHub Integration (Optional)[-]
Enable GitHub webhooks to automatically update bots when repositories change. This is optional.

[dim]Token[-]    GitHub personal access token for private repo access (create at github.com/settings/tokens)
[dim]Secret[-]   Random string to secure GitHub webhooks (min 8 characters - use anything, e.g., "mysecret123")

Leave both blank to skip. You can add this later by editing .env and docker-compose.yml.`

	w.setContent(form, 5, "Enter:save  Esc:skip  GitHub webhook is optional", helpText)

	if err := w.app.Run(); err != nil {
		return err
	}

	if w.result != nil {
		return w.result
	}

	return nil
}

// stepSelectProviders runs Step 6: select LLM providers (multi-select list).
func (w *WizardTUI) stepSelectProviders() error {
	w.currentStep = 6

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

	helpText := `[yellow]💡 LLM Providers[-]
Select AI services that power Bot Army's intelligent features. The system will try providers in order.

[dim]• Ollama[-]        Free local AI model - runs on your computer (great for learning)
[dim]• OpenRouter[-]    Access to many models (Claude, GPT, Llama, etc) via single API
[dim]• Anthropic[-]     Official Claude API - best for production use
[dim]• OpenAI[-]        GPT models - alternative high-quality provider
[dim]• Tip[-]           You can select multiple providers - they act as fallbacks if one fails`

	w.setContent(list, 6, "↑↓:nav  Space:toggle  Enter:next  Esc:cancel  q:quit", helpText)

	if err := w.app.Run(); err != nil {
		return err
	}

	if w.result != nil {
		return w.result
	}
	if !done {
		return fmt.Errorf("step 6 cancelled")
	}

	return nil
}

// stepConfigureEnvVars runs Step 7: configure environment variables (form).
func (w *WizardTUI) stepConfigureEnvVars() error {
	w.currentStep = 7

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

	helpText := `[yellow]💡 Environment Variables[-]
Optional settings for advanced customization (leave blank for defaults).
[dim]• API Keys[-]          Credentials for external services
[dim]• Feature Flags[-]     Enable/disable specific features
[dim]• Timeouts[-]          Customize response wait times
Most users can skip this step and use defaults.`

	w.setContent(form, 7, "Enter:save  Esc:cancel", helpText)

	if err := w.app.Run(); err != nil {
		return err
	}

	if w.result != nil {
		return w.result
	}

	return nil
}

// stepConfigureTerminalContext runs Step 8: configure terminal context helper (optional).
func (w *WizardTUI) stepConfigureTerminalContext() error {
	w.currentStep = 8

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

	helpText := `[yellow]💡 Terminal Context Helper (Optional)[-]
bot-army-shell adds context awareness to your terminal.
[dim]• Ctrl+B menu[-]       Quick access to Bot Army commands and status
[dim]• Auto-detection[-]     Detects when you enter bot directories
[dim]• Smart suggestions[-]  Recommends relevant operations
You can install this later via make shell-install.`

	w.setContent(list, 8, "Space:toggle  Enter:save  Esc:cancel", helpText)

	if err := w.app.Run(); err != nil {
		return err
	}

	if w.result != nil {
		return w.result
	}
	if !done {
		return fmt.Errorf("step 8 cancelled")
	}

	return nil
}

// stepConfigureVolumes runs Step 9: configure custom volume mounts.
func (w *WizardTUI) stepConfigureVolumes() error {
	w.currentStep = 9

	form := tview.NewForm()
	form.SetBorder(true).
		SetTitle(" Configure Custom Volume Mounts (Optional)  Enter:save  Esc:skip ").
		SetTitleAlign(tview.AlignLeft)

	// Input fields for a single volume mount (can add more by editing docker-compose.yml later)
	sourceInput := ""
	destInput := ""

	form.AddInputField("Host Path (e.g., /Users/you/data)", "", 60, nil, func(text string) {
		sourceInput = text
	})

	form.AddInputField("Container Path (e.g., /data)", "", 60, nil, func(text string) {
		destInput = text
	})

	form.AddButton("Add Mount", func() {
		if sourceInput != "" && destInput != "" {
			w.cfg.CustomMounts = append(w.cfg.CustomMounts, CustomMount{
				Source:      sourceInput,
				Destination: destInput,
			})
		}
		w.app.Stop()
	})

	form.AddButton("Skip", func() {
		w.cfg.CustomMounts = nil
		w.app.Stop()
	})

	helpText := `[yellow]💡 Custom Volume Mounts[-]
Volumes let containers access your computer's files and folders. This is optional - you can add mounts later.

[dim]• Host Path[-]           Full path on your computer (e.g., /Users/you/projects)
[dim]• Container Path[-]      Where it appears inside the container (e.g., /projects)

Examples:
  /Users/you/data → /data                 Share a data folder with bots
  /Users/you/.ssh → /root/.ssh            Share SSH keys for git operations
  /Users/you/Documents → /workspace       Share your documents folder

Leave both fields empty to skip. You can always add volumes later by editing docker-compose.yml.`

	w.setContent(form, 9, "Tab:next field  Enter:add  Esc:skip", helpText)

	if err := w.app.Run(); err != nil {
		return err
	}

	if w.result != nil {
		return w.result
	}

	return nil
}

// stepReviewAndConfirm runs final review and confirm (text view).
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

	if len(w.cfg.CustomMounts) > 0 {
		summary += "\n[cyan]Custom Volume Mounts[-]\n"
		for _, mount := range w.cfg.CustomMounts {
			summary += "  • " + mount.Source + " → " + mount.Destination + "\n"
		}
	}

	summary += "\n[cyan]Integration Flags[-]\n"
	enabledCount := 0
	for _, enabled := range w.cfg.EnabledIntegrations {
		if enabled {
			enabledCount++
		}
	}
	summary += "  " + fmt.Sprintf("%d of 8 integrations enabled\n", enabledCount)

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

	helpText := `[yellow]💡 Review Your Configuration[-]
Review all settings below before creating your Bot Army installation. This is your final chance to make changes.

[dim]✓[-] Press [green]Enter[-] to create docker-compose.yml, download bot repos, and start the system
[dim]✗[-] Press [yellow]Esc[-] to go back and modify any settings
[dim]Next steps[-] After setup completes, run [green]docker compose up -d[-] to start all services`

	w.setContent(review, 10, "Enter:start setup  Esc:back  q:quit", helpText)

	if err := w.app.Run(); err != nil {
		return err
	}

	if !confirmed {
		return fmt.Errorf("setup cancelled")
	}

	return nil
}
