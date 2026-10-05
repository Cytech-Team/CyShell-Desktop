package main

import (
	"fmt"
	"os"

	"github.com/AvengeMedia/dankgo/ipc"
	"github.com/Cytech-Team/CyShell-Desktop/core/internal/notify"
	"github.com/spf13/cobra"
)

var (
	notifyAppName string
	notifyIcon    string
	notifyFile    string
	notifyTimeout int
)

var notifyCmd = &cobra.Command{
	Use:   "notify <summary> [body]",
	Short: "Send a desktop notification",
	Long: `Send a desktop notification with optional actions.

If --file is provided, the notification will have "Open" and "Open Folder" actions.

Examples:
  cyshell notify "Hello" "World"
  cyshell notify "File received" "photo.jpg" --file ~/Downloads/photo.jpg --icon smartphone
  cyshell notify "Download complete" --file ~/Downloads/file.zip --app "My App"`,
	Args: cobra.MinimumNArgs(1),
	Run:  runNotify,
}

var genericNotifyActionCmd = &cobra.Command{
	Use:    "notify-action-generic",
	Hidden: true,
	Run: func(cmd *cobra.Command, args []string) {
		notify.RunActionListener(args)
	},
}

func init() {
	notifyCmd.Flags().StringVar(&notifyAppName, "app", "CyShell", "Application name")
	notifyCmd.Flags().StringVar(&notifyIcon, "icon", "", "Icon name or path")
	notifyCmd.Flags().StringVar(&notifyFile, "file", "", "File path (enables Open/Open Folder actions)")
	notifyCmd.Flags().IntVar(&notifyTimeout, "timeout", 5000, "Timeout in milliseconds")
}

func runNotify(cmd *cobra.Command, args []string) {
	summary := args[0]
	body := ""
	if len(args) > 1 {
		body = args[1]
	}

	n := notify.Notification{
		AppName:  notifyAppName,
		Icon:     notifyIcon,
		Summary:  summary,
		Body:     body,
		FilePath: notifyFile,
		Timeout:  int32(notifyTimeout),
	}

	id, err := notify.Send(n)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	if n.FilePath == "" {
		return
	}
	watchNotificationAction(id, n.FilePath)
}

func watchNotificationAction(id uint32, path string) {
	if id == 0 {
		return
	}
	resp, ok := tryServerRequest(ipc.Request{
		Method: "notify.watchAction",
		Params: map[string]any{"id": id, "path": path},
	})
	if ok && resp.Error == "" {
		return
	}
	notify.SpawnActionListener(id, path)
}
