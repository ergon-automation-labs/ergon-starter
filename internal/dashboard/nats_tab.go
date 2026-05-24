package dashboard

import (
	"context"

	"github.com/nats-io/nats.go"
	"github.com/rivo/tview"
)

// NATSTab provides NATS request/reply testing.
type NATSTab struct {
	widget  *tview.Flex
	form    *tview.Form
	output  *tview.TextView
	nc      *nats.Conn
	ctx     context.Context
	cancel  context.CancelFunc
}

// NewNATSTab creates a new NATS tab.
func NewNATSTab() *NATSTab {
	return &NATSTab{}
}

// Widget returns the tab's root widget.
func (n *NATSTab) Widget() tview.Primitive {
	return n.widget
}

// Init initializes the NATS tab.
func (n *NATSTab) Init(app *tview.Application, cfg *DashboardConfig) {
	n.ctx, n.cancel = context.WithCancel(context.Background())

	// Form for subject/body input
	n.form = tview.NewForm()
	n.form.SetBorder(true).
		SetTitle(" NATS Explorer ").
		SetTitleAlign(tview.AlignLeft)

	n.form.AddInputField("Subject", "system.health.", 40, nil, nil)
	n.form.AddInputField("Body", "{}", 40, nil, nil)
	n.form.AddButton("Send", func() {
		// TODO: send request
	})
	n.form.AddButton("Disconnect", func() {
		// TODO: handle disconnect/reconnect
	})

	// Output view
	n.output = tview.NewTextView()
	n.output.SetBorder(true).
		SetTitle(" Response ").
		SetTitleAlign(tview.AlignLeft)
	n.output.SetDynamicColors(true)

	// Layout
	n.widget = tview.NewFlex().SetDirection(tview.FlexRow).
		AddItem(n.form, 8, 0, true).
		AddItem(n.output, 0, 1, false)

	// Try to connect to NATS
	natsURL := "nats://localhost:" + cfg.NATSPort
	var err error
	n.nc, err = nats.Connect(natsURL)
	if err != nil {
		n.output.SetText("[red]Failed to connect to NATS[-]\nError: " + err.Error())
	} else {
		n.output.SetText("[green]Connected to NATS[-]")
	}
}

// Stop stops the NATS tab.
func (n *NATSTab) Stop() {
	if n.cancel != nil {
		n.cancel()
	}
	if n.nc != nil {
		n.nc.Close()
	}
}
