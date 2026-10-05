package main

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/Cytech-Team/CyShell-Desktop/core/internal/keybinds"
	"github.com/Cytech-Team/CyShell-Desktop/core/internal/keybinds/providers"
	"github.com/Cytech-Team/CyShell-Desktop/core/internal/log"
	"github.com/spf13/cobra"
)

var keybindsCmd = &cobra.Command{
	Use:     "keybinds",
	Aliases: []string{"cheatsheet", "chsht"},
	Short:   "Manage keybinds and cheatsheets",
	Long:    "Display and manage keybinds and cheatsheets for various applications",
}

var keybindsListCmd = &cobra.Command{
	Use:   "list",
	Short: "List available providers",
	Long:  "List all available keybind/cheatsheet providers",
	Run:   runKeybindsList,
}

var keybindsShowCmd = &cobra.Command{
	Use:   "show <provider>",
	Short: "Show keybinds for a provider",
	Long:  "Display keybinds/cheatsheet for the specified provider",
	Args:  cobra.ExactArgs(1),
	ValidArgsFunction: func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		if len(args) != 0 {
			return nil, cobra.ShellCompDirectiveNoFileComp
		}
		registry := keybinds.GetDefaultRegistry()
		return registry.List(), cobra.ShellCompDirectiveNoFileComp
	},
	Run: runKeybindsShow,
}

var keybindsSetCmd = &cobra.Command{
	Use:   "set <provider> <key> <action>",
	Short: "Set a keybind override",
	Long:  "Create or update a keybind override for the specified provider",
	Args:  cobra.ExactArgs(3),
	Run:   runKeybindsEdit,
}

var keybindsRemoveCmd = &cobra.Command{
	Use:   "remove <provider> <key>",
	Short: "Remove a keybind",
	Long:  "Remove a keybind override. Provider-specific backends preserve their own safe override semantics instead of rewriting unrelated user bindings.",
	Args:  cobra.ExactArgs(2),
	Run:   runKeybindsEdit,
}

var keybindsResetCmd = &cobra.Command{
	Use:   "reset <provider> <key>",
	Short: "Reset a keybind override to its CyShell default",
	Long:  "Drop the user override for the given key so the underlying compositor/default binding can apply again when one exists.",
	Args:  cobra.ExactArgs(2),
	Run:   runKeybindsEdit,
}

var keybindsResetAllCmd = &cobra.Command{
	Use:   "reset-all <provider>",
	Short: "Reset all CyShell-managed keybind overrides",
	Long:  "Remove the provider's CyShell-managed overrides while preserving user-owned bindings and configuration.",
	Args:  cobra.ExactArgs(1),
	Run:   runKeybindsResetAll,
}

func init() {
	for _, command := range []*cobra.Command{keybindsSetCmd, keybindsRemoveCmd, keybindsResetCmd, keybindsResetAllCmd} {
		command.Flags().Bool("json", false, "Return structured mutation results, including errors")
	}
	keybindsListCmd.Flags().BoolP("json", "j", false, "Output as JSON")
	keybindsShowCmd.Flags().String("path", "", "Override config path for the provider")
	keybindsSetCmd.Flags().String("desc", "", "Description for hotkey overlay")
	keybindsSetCmd.Flags().Bool("allow-when-locked", false, "Allow when screen is locked")
	keybindsSetCmd.Flags().Int("cooldown-ms", 0, "Cooldown in milliseconds")
	keybindsSetCmd.Flags().Bool("no-repeat", false, "Disable key repeat")
	keybindsSetCmd.Flags().Bool("no-inhibiting", false, "Keep bind active when shortcuts are inhibited (allow-inhibiting=false)")
	keybindsSetCmd.Flags().String("replace-key", "", "Original key to replace (removes old key)")

	keybindsCmd.AddCommand(keybindsListCmd)
	keybindsCmd.AddCommand(keybindsShowCmd)
	keybindsCmd.AddCommand(keybindsSetCmd)
	keybindsCmd.AddCommand(keybindsRemoveCmd)
	keybindsCmd.AddCommand(keybindsResetCmd)
	keybindsCmd.AddCommand(keybindsResetAllCmd)

	keybinds.SetJSONProviderFactory(func(filePath string) (keybinds.Provider, error) {
		return providers.NewJSONFileProvider(filePath)
	})

	initializeProviders()
}

func initializeProviders() {
	registry := keybinds.GetDefaultRegistry()
	if err := registry.Register(providers.NewLabwcProvider("")); err != nil {
		log.Warnf("Failed to register Labwc provider: %v", err)
	}
}

func runKeybindsList(cmd *cobra.Command, _ []string) {
	providerList := keybinds.GetDefaultRegistry().List()
	asJSON, _ := cmd.Flags().GetBool("json")

	if asJSON {
		output, _ := json.Marshal(providerList)
		fmt.Fprintln(os.Stdout, string(output))
		return
	}

	if len(providerList) == 0 {
		fmt.Fprintln(os.Stdout, "No providers available")
		return
	}

	fmt.Fprintln(os.Stdout, "Available providers:")
	for _, name := range providerList {
		fmt.Fprintf(os.Stdout, "  - %s\n", name)
	}
}

func makeProviderWithPath(name, path string) keybinds.Provider {
	if name == "labwc" {
		return providers.NewLabwcProvider(path)
	}
	return nil
}

func printCheatSheet(provider keybinds.Provider) {
	sheet, err := provider.GetCheatSheet()
	if err != nil {
		log.Fatalf("Error getting cheatsheet: %v", err)
	}
	output, err := json.MarshalIndent(sheet, "", "  ")
	if err != nil {
		log.Fatalf("Error generating JSON: %v", err)
	}
	fmt.Fprintln(os.Stdout, string(output))
}

func runKeybindsShow(cmd *cobra.Command, args []string) {
	providerName := args[0]
	customPath, _ := cmd.Flags().GetString("path")

	if customPath != "" {
		provider := makeProviderWithPath(providerName, customPath)
		if provider == nil {
			log.Fatalf("Provider %s does not support custom path", providerName)
		}
		printCheatSheet(provider)
		return
	}

	provider, err := keybinds.GetDefaultRegistry().Get(providerName)
	if err != nil {
		log.Fatalf("Error: %v", err)
	}
	printCheatSheet(provider)
}

func keybindEditFailure(err error) map[string]any {
	return map[string]any{"success": false, "code": "command_failed", "message": err.Error()}
}

func runKeybindsEdit(cmd *cobra.Command, args []string) {
	result, err := editKeybind(cmd, args)
	if err == nil {
		_ = json.NewEncoder(cmd.OutOrStdout()).Encode(result)
		return
	}
	structured, _ := cmd.Flags().GetBool("json")
	if !structured {
		log.Fatalf("Failed to save keybind: %v", err)
		return
	}
	_ = json.NewEncoder(cmd.OutOrStdout()).Encode(keybindEditFailure(err))
	os.Exit(1)
}

func runKeybindsResetAll(cmd *cobra.Command, args []string) {
	provider, err := keybinds.GetDefaultRegistry().Get(args[0])
	if err == nil {
		bulkResettable, ok := provider.(keybinds.BulkResettableProvider)
		if !ok {
			err = fmt.Errorf("provider %s does not support resetting all managed keybinds", args[0])
		} else {
			var resetCount int
			resetCount, err = bulkResettable.ResetAllManagedBinds()
			if err == nil {
				_ = json.NewEncoder(cmd.OutOrStdout()).Encode(map[string]any{
					"success": true,
					"reset":   resetCount,
					"path":    bulkResettable.GetOverridePath(),
				})
				return
			}
		}
	}
	structured, _ := cmd.Flags().GetBool("json")
	if !structured {
		log.Fatalf("Failed to reset keybinds: %v", err)
		return
	}
	_ = json.NewEncoder(cmd.OutOrStdout()).Encode(keybindEditFailure(err))
	os.Exit(1)
}

func editKeybind(cmd *cobra.Command, args []string) (map[string]any, error) {
	provider, err := keybinds.GetDefaultRegistry().Get(args[0])
	if err != nil {
		return nil, err
	}
	key := args[1]
	writable, ok := provider.(keybinds.WritableProvider)
	if !ok {
		return nil, fmt.Errorf("provider %s does not support writing keybinds", args[0])
	}
	result := map[string]any{"success": true, "key": key}
	switch cmd.Name() {
	case "set":
		options := make(map[string]any)
		if v, _ := cmd.Flags().GetBool("allow-when-locked"); v {
			options["allow-when-locked"] = true
		}
		if v, _ := cmd.Flags().GetBool("no-inhibiting"); v {
			options["override-inhibition"] = true
		}
		replaceKey, _ := cmd.Flags().GetString("replace-key")
		desc, _ := cmd.Flags().GetString("desc")
		if replaceKey != "" && replaceKey != key {
			if replacer, ok := provider.(keybinds.ReplacingProvider); ok {
				err = replacer.ReplaceBind(replaceKey, key, args[2], desc, options)
			} else {
				if removeErr := writable.RemoveBind(replaceKey); removeErr != nil {
					err = removeErr
				} else {
					err = writable.SetBind(key, args[2], desc, options)
				}
			}
		} else {
			err = writable.SetBind(key, args[2], desc, options)
		}
		result["action"] = args[2]
		result["path"] = writable.GetOverridePath()
	case "remove":
		err = writable.RemoveBind(key)
		result["removed"] = true
	case "reset":
		err = writable.ResetBind(key)
		result["reset"] = true
	default:
		return nil, fmt.Errorf("unsupported keybind operation: %s", cmd.Name())
	}
	return result, err
}
