package wizard

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	titleStyle    = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("205"))
	selectedStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("120"))
	lockedStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
	cursorStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("205"))
	hintStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
)

// --- Bot selector ---

type botSelectorModel struct {
	bots      []Bot
	selected  map[int]bool
	cursor    int
	done      bool
	cancelled bool
}

func (m *botSelectorModel) Init() tea.Cmd { return nil }

func (m *botSelectorModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			m.cancelled = true
			return m, tea.Quit
		case "enter":
			m.done = true
			return m, tea.Quit
		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down", "j":
			if m.cursor < len(m.bots)-1 {
				m.cursor++
			}
		case " ", "x":
			bot := m.bots[m.cursor]
			if !bot.IsCore() {
				m.selected[m.cursor] = !m.selected[m.cursor]
			}
		}
	}
	return m, nil
}

func (m *botSelectorModel) View() string {
	var b strings.Builder

	b.WriteString(titleStyle.Render("🤖 Bot Army Setup"))
	b.WriteString("\n\n")
	b.WriteString("Select bots to install ")
	b.WriteString(hintStyle.Render("(↑↓:nav  space:toggle  enter:confirm)"))
	b.WriteString("\n\n")

	for i, bot := range m.bots {
		cursor := "  "
		if i == m.cursor {
			cursor = cursorStyle.Render("▸ ")
		}

		check := "[ ]"
		label := bot.DisplayName()

		if m.selected[i] {
			check = selectedStyle.Render("[✓]")
			label = selectedStyle.Render(label)
		}

		if bot.IsCore() {
			check = lockedStyle.Render("[✓]")
			label = lockedStyle.Render(fmt.Sprintf("%s (required)", bot.DisplayName()))
		}

		b.WriteString(fmt.Sprintf("%s%s %s\n", cursor, check, label))
	}

	b.WriteString("\n")
	b.WriteString(hintStyle.Render("q: cancel"))
	return b.String()
}

// --- Provider selector ---

type providerSelectorModel struct {
	providers []Provider
	selected  map[int]bool
	cursor    int
	done      bool
	cancelled bool
}

func (m *providerSelectorModel) Init() tea.Cmd { return nil }

func (m *providerSelectorModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			m.cancelled = true
			return m, tea.Quit
		case "enter":
			m.done = true
			return m, tea.Quit
		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down", "j":
			if m.cursor < len(m.providers)-1 {
				m.cursor++
			}
		case " ", "x":
			m.selected[m.cursor] = !m.selected[m.cursor]
		}
	}
	return m, nil
}

func (m *providerSelectorModel) View() string {
	var b strings.Builder

	b.WriteString(titleStyle.Render("LLM Providers"))
	b.WriteString("\n\n")
	b.WriteString("Select providers to enable ")
	b.WriteString(hintStyle.Render("(↑↓:nav  space:toggle  enter:confirm)"))
	b.WriteString("\n\n")

	for i, p := range m.providers {
		cursor := "  "
		if i == m.cursor {
			cursor = cursorStyle.Render("▸ ")
		}

		check := "[ ]"
		label := p.Label
		if m.selected[i] {
			check = selectedStyle.Render("[✓]")
			label = selectedStyle.Render(label)
		}

		b.WriteString(fmt.Sprintf("%s%s %s\n", cursor, check, label))
	}

	b.WriteString("\n")
	b.WriteString(hintStyle.Render("At least one provider required  •  q: cancel"))
	return b.String()
}
