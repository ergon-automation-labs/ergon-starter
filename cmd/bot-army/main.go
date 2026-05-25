package main

import (
	"fmt"
	"os"

	"github.com/abby/bot-army-starter/internal/dashboard"
	"github.com/abby/bot-army-starter/internal/wizard"
)

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	switch os.Args[1] {
	case "init":
		if err := wizard.RunInit(); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "add":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Usage: bot-army add <bot-name>\n")
			os.Exit(1)
		}
		if err := wizard.RunAdd(os.Args[2]); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "status":
		if err := wizard.RunStatus(); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "dashboard":
		if err := dashboard.RunFromDir("."); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	default:
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Println(`bot-army - Bot Army starter toolkit

Commands:
  init        Interactive setup wizard
  add         Add a bot to your installation
  status      Show running services
  dashboard   Monitor running fleet`)
}
