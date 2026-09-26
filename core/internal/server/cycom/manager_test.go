package cycom

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDefaultStateDirUsesXDGStateHome(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", "/tmp/cyshell-state-test")
	got := defaultStateDir()
	want := filepath.Join("/tmp/cyshell-state-test", "cycomagent")
	if got != want {
		t.Fatalf("defaultStateDir() = %q, want %q", got, want)
	}
}

func TestDefaultStateDirFallsBack(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", "")
	got := defaultStateDir()
	if got == "" {
		t.Fatal("defaultStateDir() returned empty path")
	}
}

func TestNewManagerRegistersCyShellTools(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]bool{
		"shell_get_state":       false,
		"shell_settings_get":    false,
		"shell_settings_search": false,
		"shell_settings_set":    false,
		"shell_open_settings":   false,
		"shell_launcher":        false,
		"shell_control_center":  false,
		"shell_query_ui":        false,
		"window_list":           false,
		"window_control":        false,
		"workspace_list":        false,
		"workspace_focus":       false,
		"desktop_get_context":   false,
		"desktop_query":         false,
		"desktop_action":        false,
		"desktop_receipts":      false,
		"desktop_undo":          false,
		"app_query_ui":          false,
	}
	for _, tool := range manager.runtime.ListTools() {
		if _, ok := want[tool.Name]; ok {
			want[tool.Name] = true
		}
	}
	for name, found := range want {
		if !found {
			t.Fatalf("missing native CyShell tool %s", name)
		}
	}
}

func TestRuntimeGateAllowsReadsAndBlocksControl(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if !manager.State().Enabled || !manager.State().ControlEnabled {
		t.Fatalf("new manager should be enabled: %#v", manager.State())
	}
	if err := manager.SetControlEnabled(false); err != nil {
		t.Fatal(err)
	}
	gate := runtimeGate{manager: manager}
	args := json.RawMessage(`{"reason":"test control gate"}`)
	if err := gate.BeforeCall(context.Background(), "system_info", args); err != nil {
		t.Fatalf("read-only system_info should remain available: %v", err)
	}
	if err := gate.BeforeCall(context.Background(), "process_exec", args); err == nil || !strings.Contains(err.Error(), "control is disabled") {
		t.Fatalf("mutating tool should be blocked by control gate, got %v", err)
	}
}

func TestPermissionScopesBlockOnlyTheirDomain(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	gate := runtimeGate{manager: manager}
	args := json.RawMessage(`{"reason":"permission scope test"}`)
	if err := manager.setAppPolicyWithoutCancel("app:focused", "Focused application", "app.read", "allow"); err != nil {
		t.Fatal(err)
	}

	if err := manager.SetPermission("app.control", false); err != nil {
		t.Fatal(err)
	}
	if err := gate.BeforeCall(context.Background(), "anyapp_click", args); err == nil || !strings.Contains(err.Error(), "app.control") {
		t.Fatalf("expected app.control denial, got %v", err)
	}
	if err := gate.BeforeCall(context.Background(), "window_control", args); err != nil {
		t.Fatalf("window.control should stay independent: %v", err)
	}
	if err := gate.BeforeCall(context.Background(), "anyapp_get_app_state", args); err != nil {
		t.Fatalf("app.read should remain available: %v", err)
	}
}

func TestScreenshotPermissionIsArgumentAware(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if err := manager.SetPermission("screen.capture", false); err != nil {
		t.Fatal(err)
	}
	gate := runtimeGate{manager: manager}
	if err := manager.setAppPolicyWithoutCancel("app:focused", "Focused application", "app.read", "allow"); err != nil {
		t.Fatal(err)
	}
	without := json.RawMessage(`{"reason":"semantic only","include_screenshot":false}`)
	if err := gate.BeforeCall(context.Background(), "anyapp_get_app_state", without); err != nil {
		t.Fatalf("semantic app read should work without screenshot permission: %v", err)
	}
	with := json.RawMessage(`{"reason":"need screenshot","include_screenshot":true}`)
	if err := gate.BeforeCall(context.Background(), "anyapp_get_app_state", with); err == nil || !strings.Contains(err.Error(), "screen.capture") {
		t.Fatalf("expected screen.capture denial, got %v", err)
	}
}

func TestPermissionStatePersists(t *testing.T) {
	stateHome := t.TempDir()
	t.Setenv("XDG_STATE_HOME", stateHome)
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if err := manager.SetPermission("files.write", false); err != nil {
		t.Fatal(err)
	}
	reloaded, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if reloaded.permissionEnabled("files.write") {
		t.Fatal("files.write permission should remain disabled after reload")
	}
	if !reloaded.permissionEnabled("files.read") {
		t.Fatal("files.read permission should remain enabled")
	}
}

func TestEmergencyStopPersists(t *testing.T) {
	stateHome := t.TempDir()
	t.Setenv("XDG_STATE_HOME", stateHome)
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if err := manager.EmergencyStop(); err != nil {
		t.Fatal(err)
	}
	if manager.State().ControlEnabled {
		t.Fatal("emergency stop should disable control")
	}
	if _, err := os.Stat(filepath.Join(stateHome, "cycomagent", "cyshell-agent-control.json")); err != nil {
		t.Fatalf("control state was not persisted: %v", err)
	}
	reloaded, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if reloaded.State().ControlEnabled {
		t.Fatal("reloaded manager should preserve emergency-stop control state")
	}
}
