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
	if err := w.stepSelectBots(); err != nil {
		return err
	}
	if err := w.stepConfigurePorts(); err != nil {
		return err
	}
	if err := w.stepSelectProviders(); err != nil {
		return err
	}
	if err := w.stepConfigureEnvVars(); err != nil {
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

// setHeader updates the header text with step indicator.
func (w *WizardTUI) setHeader(title string) {
	stepIndicator := ""
	if w.currentStep > 0 && w.currentStep <= 5 {
		steps := []rune{'●', '●', '●', '●', '●'}
		for i := w.currentStep; i < 5; i++ {
			steps[i] = '○'
		}
		stepIndicator = fmt.Sprintf("  %s  Step %d/5", string(steps), w.currentStep)
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

// stepSelectBots runs Step 1: select bots (multi-select list).
func (w *WizardTUI) stepSelectBots() error {
	w.currentStep = 1

	list := tview.NewList()
	list.SetBorder(true).
		SetTitle(" Select Bots  ↑↓:nav  Space:toggle  Enter:next ").
		SetTitleAlign(tview.AlignLeft)

	// Track selection: core bots locked on, others start deselected
	selected := make(map[int]bool)
	for i, b := range w.cfg.AllBots {
		if b.IsCore() {
			selected[i] = true
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
			list.AddItem(prefix+b.Name, b.App, 0, nil)
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

	w.setContent(list, 1, "↑↓:nav  Space:toggle  Enter:next  Esc:cancel  q:quit")

	// Run the app until this step completes
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

// stepConfigurePorts runs Step 2: configure host ports (form).
func (w *WizardTUI) stepConfigurePorts() error {
	w.currentStep = 2

	form := tview.NewForm()
	form.SetBorder(true).
		SetTitle(" Configure Ports  Enter:save  Esc:cancel ").
		SetTitleAlign(tview.AlignLeft)

	form.AddInputField("NATS port", w.cfg.Ports.NATS, 10, nil, nil)
	form.AddInputField("NATS monitor port", w.cfg.Ports.NATSMonitor, 10, nil, nil)
	form.AddInputField("PostgreSQL port", w.cfg.Ports.Postgres, 10, nil, nil)
	form.AddInputField("Ollama port", w.cfg.Ports.Ollama, 10, nil, nil)

	form.AddButton("Next", func() {
		w.cfg.Ports.NATS = form.GetFormItem(0).(*tview.InputField).GetText()
		w.cfg.Ports.NATSMonitor = form.GetFormItem(1).(*tview.InputField).GetText()
		w.cfg.Ports.Postgres = form.GetFormItem(2).(*tview.InputField).GetText()
		w.cfg.Ports.Ollama = form.GetFormItem(3).(*tview.InputField).GetText()
		w.app.Stop()
	})

	form.AddButton("Cancel", func() {
		w.result = fmt.Errorf("cancelled")
		w.app.Stop()
	})

	w.setContent(form, 2, "Enter:save  Esc:cancel")

	if err := w.app.Run(); err != nil {
		return err
	}

	if w.result != nil {
		return w.result
	}

	return nil
}

// stepSelectProviders runs Step 3: select LLM providers (multi-select list).
func (w *WizardTUI) stepSelectProviders() error {
	w.currentStep = 3

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

	w.setContent(list, 3, "↑↓:nav  Space:toggle  Enter:next  Esc:cancel  q:quit")

	if err := w.app.Run(); err != nil {
		return err
	}

	if w.result != nil {
		return w.result
	}
	if !done {
		return fmt.Errorf("step 3 cancelled")
	}

	return nil
}

// stepConfigureEnvVars runs Step 4: configure environment variables (form).
func (w *WizardTUI) stepConfigureEnvVars() error {
	w.currentStep = 4

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

	w.setContent(form, 4, "Enter:save  Esc:cancel")

	if err := w.app.Run(); err != nil {
		return err
	}

	if w.result != nil {
		return w.result
	}

	return nil
}

// stepReviewAndConfirm runs Step 5: review and confirm (text view).
func (w *WizardTUI) stepReviewAndConfirm() error {
	w.currentStep = 5

	// Build summary text
	summary := "[yellow]Bot Army Starter Configuration[-]\n\n"
	summary += "[cyan]Selected Bots[-]\n"
	for _, b := range w.cfg.SelectedBots {
		summary += "  • " + b.Name + " (v" + b.Version + ")\n"
	}

	summary += "\n[cyan]Host Ports[-]\n"
	summary += "  NATS: " + w.cfg.Ports.NATS + "\n"
	summary += "  PostgreSQL: " + w.cfg.Ports.Postgres + "\n"
	summary += "  Ollama: " + w.cfg.Ports.Ollama + "\n"

	summary += "\n[cyan]LLM Providers[-]\n"
	for _, p := range w.cfg.SelectedProviders {
		summary += "  • " + p.Label + "\n"
	}

	summary += "\n[green]Press Enter to start setup or Esc to go back[-]"

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

	w.setContent(review, 5, "Enter:start setup  Esc:back  q:quit")

	if err := w.app.Run(); err != nil {
		return err
	}

	if !confirmed {
		return fmt.Errorf("setup cancelled")
	}

	return nil
}
