//go:build !distro_binary

package main

import (
	"fmt"

	"github.com/spf13/cobra"
)

var updateCmd = &cobra.Command{
	Use:   "update",
	Short: "Show CyShell update guidance",
	Long:  "CyShell development builds update from the CyShell repository/release channel.",
	Run: func(cmd *cobra.Command, args []string) {
		printCyShellUpdateGuidance()
	},
}

var updateCheckCmd = &cobra.Command{
	Use:   "check",
	Short: "Show CyShell update channel status",
	Long:  "Report the update policy for this CyShell development build.",
	Run: func(cmd *cobra.Command, args []string) {
		printCyShellUpdateGuidance()
	},
}

func printCyShellUpdateGuidance() {
	fmt.Println("CyShell development update channel")
	fmt.Println("Repository: https://github.com/Cytech-Team/CyShell-Desktop")
	fmt.Println("Branch: cyshell-dev")
	fmt.Println()
	fmt.Println("Update from the CyShell repository/release channel, then rebuild and restart cyshell.service.")
}
