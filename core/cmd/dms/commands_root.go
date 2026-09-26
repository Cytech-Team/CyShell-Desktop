package main

import (
	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "cyshell",
	Short: "CyShell Desktop CLI",
	Long:  "cyshell is the CyShell Desktop management CLI and backend server. The dms command remains available as a compatibility alias.",
}

func init() {
	rootCmd.PersistentFlags().StringVarP(shellApp.CustomConfigVar(), "config", "c", "", "Path to a UI config dir (containing shell.qml) to use instead of the embedded UI (compatibility env: DMS_SHELL_DIR)")
}
