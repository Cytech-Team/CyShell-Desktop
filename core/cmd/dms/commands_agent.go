package main

import (
	"encoding/json"
	"fmt"

	"github.com/AvengeMedia/dankgo/ipc"
	"github.com/spf13/cobra"
)

var agentCmd = &cobra.Command{
	Use:   "agent",
	Short: "Control the embedded CyShell Agent",
	Long:  "Open the CyShell Assistant, inspect Agent state, review pending permissions, or stop computer control immediately.",
}

var agentOpenCmd = &cobra.Command{
	Use:   "open",
	Short: "Open or focus the CyShell Assistant",
	Run: func(cmd *cobra.Command, args []string) {
		runShellIPCCommand([]string{"assistant", "focusOrToggle"})
	},
}

var agentReviewCmd = &cobra.Command{
	Use:   "review",
	Short: "Open pending Agent permission requests",
	Run: func(cmd *cobra.Command, args []string) {
		runShellIPCCommand([]string{"agent-control", "reviewPermissions"})
	},
}

var agentStopCmd = &cobra.Command{
	Use:     "stop",
	Aliases: []string{"kill", "revoke"},
	Short:   "Immediately revoke Agent computer control",
	RunE: func(cmd *cobra.Command, args []string) error {
		resp, err := sendServerRequest(ipc.Request{ID: 1, Method: "cycom.emergencyStop", Params: map[string]any{}})
		if err != nil {
			return err
		}
		if resp.Error != "" {
			return fmt.Errorf("%s", resp.Error)
		}
		if asJSON, _ := cmd.Flags().GetBool("json"); asJSON {
			if resp.Result == nil {
				fmt.Println("null")
				return nil
			}
			data, _ := json.Marshal(*resp.Result)
			fmt.Println(string(data))
			return nil
		}
		fmt.Println("CyShell Agent computer control stopped")
		return nil
	},
}

type agentActivityOrigin struct {
	Kind    string `json:"kind"`
	Name    string `json:"name"`
	Version string `json:"version,omitempty"`
}

type agentActivityItem struct {
	ID         string              `json:"id"`
	Tool       string              `json:"tool"`
	Origin     agentActivityOrigin `json:"origin"`
	Reason     string              `json:"reason,omitempty"`
	Scopes     []string            `json:"scopes,omitempty"`
	Status     string              `json:"status"`
	StartedAt  int64               `json:"startedAt"`
	FinishedAt int64               `json:"finishedAt,omitempty"`
	DurationMs int64               `json:"durationMs,omitempty"`
	Error      string              `json:"error,omitempty"`
}

var agentActivityCmd = &cobra.Command{
	Use:   "activity",
	Short: "Show or clear recent Agent tool activity",
	RunE: func(cmd *cobra.Command, args []string) error {
		clearActivity, _ := cmd.Flags().GetBool("clear")
		if clearActivity {
			resp, err := sendServerRequest(ipc.Request{ID: 1, Method: "cycom.activity.clear", Params: map[string]any{}})
			if err != nil {
				return err
			}
			if resp.Error != "" {
				return fmt.Errorf("%s", resp.Error)
			}
			fmt.Println("CyShell Agent recent activity cleared")
			return nil
		}

		resp, err := sendServerRequest(ipc.Request{ID: 1, Method: "cycom.activity.list", Params: map[string]any{}})
		if err != nil {
			return err
		}
		if resp.Error != "" {
			return fmt.Errorf("%s", resp.Error)
		}
		if resp.Result == nil {
			return fmt.Errorf("empty Agent activity response")
		}
		data, err := json.Marshal(*resp.Result)
		if err != nil {
			return err
		}
		if asJSON, _ := cmd.Flags().GetBool("json"); asJSON {
			var pretty any
			if err := json.Unmarshal(data, &pretty); err != nil {
				return err
			}
			formatted, _ := json.MarshalIndent(pretty, "", "  ")
			fmt.Println(string(formatted))
			return nil
		}
		var activity []agentActivityItem
		if err := json.Unmarshal(data, &activity); err != nil {
			return err
		}
		if len(activity) == 0 {
			fmt.Println("No recent Agent activity")
			return nil
		}
		for _, item := range activity {
			duration := ""
			if item.Status != "running" {
				duration = fmt.Sprintf(" %dms", item.DurationMs)
			}
			origin := item.Origin.Name
			if item.Origin.Version != "" {
				origin += " " + item.Origin.Version
			}
			if origin == "" {
				origin = "CyShell"
			}
			line := fmt.Sprintf("%-9s %-28s %-24s%s", item.Status, item.Tool, origin, duration)
			if item.Reason != "" {
				line += "  " + item.Reason
			}
			if item.Error != "" {
				line += "  error=" + item.Error
			}
			fmt.Println(line)
		}
		return nil
	},
}

type agentReceiptItem struct {
	ID        string `json:"id"`
	Kind      string `json:"kind"`
	Action    string `json:"action"`
	Target    string `json:"target,omitempty"`
	Value     string `json:"value,omitempty"`
	CreatedAt int64  `json:"createdAt"`
	ExpiresAt int64  `json:"expiresAt"`
	CanUndo   bool   `json:"canUndo"`
}

func loadAgentReceipts() ([]agentReceiptItem, error) {
	resp, err := sendServerRequest(ipc.Request{ID: 1, Method: "cycom.receipts.list", Params: map[string]any{}})
	if err != nil {
		return nil, err
	}
	if resp.Error != "" {
		return nil, fmt.Errorf("%s", resp.Error)
	}
	if resp.Result == nil {
		return nil, nil
	}
	data, err := json.Marshal(*resp.Result)
	if err != nil {
		return nil, err
	}
	var receipts []agentReceiptItem
	if err := json.Unmarshal(data, &receipts); err != nil {
		return nil, err
	}
	return receipts, nil
}

var agentReceiptsCmd = &cobra.Command{
	Use:   "receipts",
	Short: "Show undoable semantic Agent actions",
	RunE: func(cmd *cobra.Command, args []string) error {
		receipts, err := loadAgentReceipts()
		if err != nil {
			return err
		}
		if asJSON, _ := cmd.Flags().GetBool("json"); asJSON {
			data, _ := json.MarshalIndent(receipts, "", "  ")
			fmt.Println(string(data))
			return nil
		}
		if len(receipts) == 0 {
			fmt.Println("No undoable Agent actions")
			return nil
		}
		for _, receipt := range receipts {
			action := receipt.Action
			if receipt.Target != "" {
				action += " " + receipt.Target
			}
			if receipt.Value != "" {
				action += "=" + receipt.Value
			}
			kind := receipt.Kind
			if kind == "" {
				kind = "action"
			}
			fmt.Printf("%-16s %-9s %s\n", receipt.ID, kind, action)
		}
		return nil
	},
}

var agentUndoCmd = &cobra.Command{
	Use:   "undo [receipt-id]",
	Short: "Undo a semantic Agent machine action",
	Args:  cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		receiptID := ""
		if len(args) == 1 {
			receiptID = args[0]
		} else {
			receipts, err := loadAgentReceipts()
			if err != nil {
				return err
			}
			if len(receipts) == 0 {
				return fmt.Errorf("no undoable Agent actions")
			}
			receiptID = receipts[0].ID
		}
		resp, err := sendServerRequest(ipc.Request{ID: 1, Method: "cycom.tools.call", Params: map[string]any{
			"name":      "desktop_undo",
			"reason":    "User requested Agent rollback from dms CLI",
			"arguments": map[string]any{"receipt": receiptID},
			"origin":    map[string]any{"kind": "cli", "name": "dms agent undo"},
		}})
		if err != nil {
			return err
		}
		if resp.Error != "" {
			return fmt.Errorf("%s", resp.Error)
		}
		if asJSON, _ := cmd.Flags().GetBool("json"); asJSON {
			if resp.Result == nil {
				fmt.Println("null")
				return nil
			}
			data, _ := json.MarshalIndent(*resp.Result, "", "  ")
			fmt.Println(string(data))
			return nil
		}
		fmt.Printf("Rolled back Agent action %s\n", receiptID)
		return nil
	},
}

var agentStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show embedded Agent state",
	RunE: func(cmd *cobra.Command, args []string) error {
		resp, err := sendServerRequest(ipc.Request{ID: 1, Method: "cycom.getState", Params: map[string]any{}})
		if err != nil {
			return err
		}
		if resp.Error != "" {
			return fmt.Errorf("%s", resp.Error)
		}
		if resp.Result == nil {
			return fmt.Errorf("empty Agent state")
		}
		data, err := json.MarshalIndent(*resp.Result, "", "  ")
		if err != nil {
			return err
		}
		fmt.Println(string(data))
		return nil
	},
}

func init() {
	agentStopCmd.Flags().Bool("json", false, "Print the resulting Agent state as JSON")
	agentActivityCmd.Flags().Bool("json", false, "Print recent Agent activity as JSON")
	agentActivityCmd.Flags().Bool("clear", false, "Clear recent Agent activity")
	agentReceiptsCmd.Flags().Bool("json", false, "Print undoable Agent actions as JSON")
	agentUndoCmd.Flags().Bool("json", false, "Print rollback result as JSON")
	agentCmd.AddCommand(agentOpenCmd, agentReviewCmd, agentStopCmd, agentStatusCmd, agentActivityCmd, agentReceiptsCmd, agentUndoCmd)
}
