package cycom

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
)

type PermissionState struct {
	ID          string `json:"id"`
	Label       string `json:"label"`
	Description string `json:"description"`
	Category    string `json:"category"`
	Control     bool   `json:"control"`
	Enabled     bool   `json:"enabled"`
	Effective   bool   `json:"effective"`
}

type permissionSpec struct {
	ID          string
	Label       string
	Description string
	Category    string
	Control     bool
}

var permissionCatalog = []permissionSpec{
	{ID: "desktop.read", Label: "Read desktop", Description: "Read CyShell surfaces, desktop state and semantic UI.", Category: "Desktop", Control: false},
	{ID: "desktop.control", Label: "Control shell UI", Description: "Open, close and operate CyShell surfaces such as Settings, Launcher and Control Center.", Category: "Desktop", Control: true},
	{ID: "settings.read", Label: "Read settings", Description: "Read CyShell settings values.", Category: "Desktop", Control: false},
	{ID: "settings.write", Label: "Change settings", Description: "Modify CyShell settings values.", Category: "Desktop", Control: true},
	{ID: "window.read", Label: "Read windows", Description: "List windows and inspect focused-window state.", Category: "Windows", Control: false},
	{ID: "window.control", Label: "Control windows", Description: "Focus, close, move, resize, minimize, maximize or fullscreen windows.", Category: "Windows", Control: true},
	{ID: "workspace.read", Label: "Read workspaces", Description: "Read workspace state and membership.", Category: "Windows", Control: false},
	{ID: "workspace.control", Label: "Switch workspaces", Description: "Activate or change workspaces.", Category: "Windows", Control: true},
	{ID: "app.read", Label: "Read other apps", Description: "Inspect third-party application state through accessibility and semantic APIs.", Category: "Applications", Control: false},
	{ID: "app.control", Label: "Control other apps", Description: "Click, type, scroll, invoke actions and send input to third-party applications.", Category: "Applications", Control: true},
	{ID: "screen.capture", Label: "Capture screen", Description: "Capture screenshots or request screenshot data from an application.", Category: "Applications", Control: false},
	{ID: "device.control", Label: "Control device hardware", Description: "Change Wi-Fi radio, Bluetooth, audio, microphone, brightness and power profile state.", Category: "Computer", Control: true},
	{ID: "files.read", Label: "Read files", Description: "List, search, stat and read local files.", Category: "Computer", Control: false},
	{ID: "files.write", Label: "Change files", Description: "Create, patch, move or remove local files.", Category: "Computer", Control: true},
	{ID: "system.read", Label: "Read system", Description: "Inspect processes, jobs, environment, displays, policy, audit and system state.", Category: "Computer", Control: false},
	{ID: "system.control", Label: "Control system", Description: "Run processes, manage services, jobs, displays, runtime state and policy reloads.", Category: "Computer", Control: true},
	{ID: "network.access", Label: "Network access", Description: "Resolve names and make outbound network requests or connections.", Category: "Network", Control: true},
	{ID: "remote.read", Label: "Read remote targets", Description: "List, inspect and probe configured remote targets.", Category: "Remote", Control: false},
	{ID: "remote.control", Label: "Control remote targets", Description: "Execute, copy, add, change or remove remote targets.", Category: "Remote", Control: true},
	{ID: "power.control", Label: "Power and session control", Description: "Log out, restart or power off the machine.", Category: "Computer", Control: true},
}

func defaultPermissionMap() map[string]bool {
	out := make(map[string]bool, len(permissionCatalog))
	for _, spec := range permissionCatalog {
		out[spec.ID] = true
	}
	return out
}

func permissionSpecByID(id string) (permissionSpec, bool) {
	for _, spec := range permissionCatalog {
		if spec.ID == id {
			return spec, true
		}
	}
	return permissionSpec{}, false
}

func (m *Manager) permissionEnabled(id string) bool {
	m.permissionsMu.RLock()
	defer m.permissionsMu.RUnlock()
	return m.permissions[id]
}

func (m *Manager) Permissions() []PermissionState {
	m.permissionsMu.RLock()
	defer m.permissionsMu.RUnlock()
	items := make([]PermissionState, 0, len(permissionCatalog))
	controlEnabled := m.controlEnabled.Load()
	for _, spec := range permissionCatalog {
		enabled := m.permissions[spec.ID]
		items = append(items, PermissionState{
			ID:          spec.ID,
			Label:       spec.Label,
			Description: spec.Description,
			Category:    spec.Category,
			Control:     spec.Control,
			Enabled:     enabled,
			Effective:   enabled && (!spec.Control || controlEnabled),
		})
	}
	return items
}

func (m *Manager) SetPermission(id string, enabled bool) error {
	if _, ok := permissionSpecByID(id); !ok {
		return fmt.Errorf("unknown Agent permission %q", id)
	}
	m.permissionsMu.Lock()
	m.permissions[id] = enabled
	m.permissionsMu.Unlock()
	if !enabled {
		m.cancelActiveCalls()
	}
	err := m.persistControl()
	m.broadcastState()
	return err
}

func (m *Manager) requiredScopes(name string, raw json.RawMessage) []string {
	set := map[string]struct{}{}
	add := func(scope string) {
		if scope != "" {
			set[scope] = struct{}{}
		}
	}

	switch name {
	case "shell_get_state", "shell_query_ui", "desktop_get_context", "desktop_query", "application_search":
		add("desktop.read")
	case "desktop_action":
		add("device.control")
	case "desktop_undo":
		var args struct {
			Receipt string `json:"receipt"`
		}
		if json.Unmarshal(raw, &args) == nil {
			if record, err := m.actionReceiptForUndo(args.Receipt); err == nil && record.UndoKind == "setting" {
				add("settings.write")
				break
			}
		}
		add("device.control")
	case "desktop_receipts":
		add("desktop.read")
		for _, receipt := range m.ActionReceipts() {
			if receipt.Kind == "setting" {
				add("settings.read")
				break
			}
		}
	case "shell_settings_get", "shell_settings_search":
		add("settings.read")
	case "shell_settings_set":
		add("settings.write")
	case "shell_open_settings", "shell_launcher", "shell_control_center", "application_launch":
		add("desktop.control")
	case "window_list", "anyapp_focused_window", "anyapp_list_windows":
		add("window.read")
	case "window_control", "anyapp_activate_window", "anyapp_move_window", "anyapp_resize_window":
		add("window.control")
	case "workspace_list":
		add("workspace.read")
	case "workspace_focus":
		add("workspace.control")
	case "app_query_ui":
		// The semantic wrapper delegates to anyapp_get_app_state, which is the single
		// enforcement point for app.read and optional screen.capture consent.
	case "anyapp_doctor", "anyapp_get_app_state", "anyapp_list_apps":
		add("app.read")
	case "anyapp_click", "anyapp_drag", "anyapp_perform_action", "anyapp_press_key", "anyapp_scroll", "anyapp_set_value", "anyapp_type_text", "anyapp_setup_accessibility", "anyapp_setup_window_targeting", "desktop_input":
		add("app.control")
	case "anyapp_screenshot", "desktop_capture":
		add("screen.capture")
	case "fs_list", "fs_read", "fs_search", "fs_stat":
		add("files.read")
	case "fs_move", "fs_patch", "fs_remove", "fs_write":
		add("files.write")
	case "network_request", "network_resolve", "network_tcp":
		add("network.access")
	case "target_get", "target_list", "target_probe":
		add("remote.read")
	case "target_copy", "target_exec", "target_remove", "target_upsert":
		add("remote.control")
	case "machine_poweroff", "machine_restart", "session_logout":
		add("power.control")
	case "browser_use":
		add("app.control")
		add("network.access")
	case "system_info", "system_env", "capabilities_list", "process_inspect", "job_get", "job_list", "job_tail", "policy_get", "audit_tail", "display_outputs", "state_get", "state_list":
		add("system.read")
	case "process_exec", "process_signal", "process_spawn", "tty_control", "job_prune", "job_signal", "audit_prune", "plugins_reload", "policy_reload", "display_output_control", "state_delete", "state_put", "service_control":
		add("system.control")
	default:
		if m.toolReadOnly(name) {
			add("system.read")
		} else {
			add("system.control")
		}
	}

	if name == "anyapp_get_app_state" {
		var args map[string]any
		if json.Unmarshal(raw, &args) == nil {
			if include, ok := args["include_screenshot"].(bool); ok && include {
				add("screen.capture")
			}
			if include, ok := args["includeScreenshot"].(bool); ok && include {
				add("screen.capture")
			}
		}
	}

	out := make([]string, 0, len(set))
	for scope := range set {
		out = append(out, scope)
	}
	sort.Strings(out)
	return out
}

func (m *Manager) checkPermissions(name string, raw json.RawMessage) error {
	for _, scope := range m.requiredScopes(name, raw) {
		if m.permissionEnabled(scope) {
			continue
		}
		spec, _ := permissionSpecByID(scope)
		label := spec.Label
		if strings.TrimSpace(label) == "" {
			label = scope
		}
		return fmt.Errorf("CyShell Agent permission %q (%s) is disabled", scope, label)
	}
	return nil
}
