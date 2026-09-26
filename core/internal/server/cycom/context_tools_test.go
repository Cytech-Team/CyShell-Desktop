package cycom

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"
)

func TestSemanticAppQueryResultFiltersAccessibilityTree(t *testing.T) {
	state := map[string]any{
		"backend": "at-spi",
		"accessibility_tree": []any{
			map[string]any{"index": 1, "role": "button", "name": "Send message", "actions": []any{"click"}},
			map[string]any{"index": 2, "role": "textbox", "name": "Search"},
		},
	}
	result := semanticAppQueryResult(state, "send", 60).(map[string]any)
	if result["matchCount"] != 1 {
		t.Fatalf("matchCount = %#v, want 1", result["matchCount"])
	}
	matches := result["matches"].([]map[string]any)
	if len(matches) != 1 {
		t.Fatalf("matches = %#v", matches)
	}
}

func TestNormalizeRuntimeResultPrefersStructuredPayload(t *testing.T) {
	value := map[string]any{
		"structured": map[string]any{"ok": true, "backend": "at-spi"},
		"content":    []any{map[string]any{"type": "text", "text": "fallback"}},
	}
	got := normalizeRuntimeResult(value)
	data, _ := json.Marshal(got)
	if string(data) != `{"backend":"at-spi","ok":true}` {
		t.Fatalf("normalized = %s", data)
	}
}

func TestDeviceControlPermissionProtectsDesktopAction(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if err := manager.SetPermission("device.control", false); err != nil {
		t.Fatal(err)
	}
	gate := runtimeGate{manager: manager}
	raw := json.RawMessage(`{"action":"wifi.disable","reason":"test"}`)
	if err := gate.BeforeCall(t.Context(), "desktop_action", raw); err == nil {
		t.Fatal("desktop_action should require device.control")
	}
}

func TestSemanticAppProjectionCollapsesRepeatedNodes(t *testing.T) {
	state := map[string]any{
		"backend": "at-spi",
		"accessibility_tree": []any{
			map[string]any{"role": "label", "name": "row"},
			map[string]any{"role": "label", "name": "row"},
			map[string]any{"role": "button", "name": "Save", "actions": []any{"click"}},
		},
	}
	result := semanticAppQueryResult(state, "", 60).(map[string]any)
	matches := result["matches"].([]map[string]any)
	if len(matches) != 2 {
		t.Fatalf("expected repeated nodes to collapse, got %#v", matches)
	}
	if matches[0]["repeatCount"] != 2 {
		t.Fatalf("repeatCount = %#v, want 2", matches[0]["repeatCount"])
	}
}

func TestSemanticAppProjectionWalksNestedTreeAndTruncates(t *testing.T) {
	children := []any{}
	for i := 0; i < 8; i++ {
		children = append(children, map[string]any{"role": "button", "name": fmt.Sprintf("Action %d", i), "actions": []any{"click"}})
	}
	state := map[string]any{
		"accessibility_tree": map[string]any{
			"role":     "window",
			"name":     "Demo",
			"children": children,
		},
	}
	result := semanticAppQueryResult(state, "Action", 3).(map[string]any)
	if result["sourceNodeCount"] != 9 {
		t.Fatalf("sourceNodeCount = %#v, want 9", result["sourceNodeCount"])
	}
	if result["returnedCount"] != 3 || result["truncated"] != true {
		t.Fatalf("unexpected truncation result: %#v", result)
	}
}

func TestFinalizeDesktopContextReturnsCompactUnchangedResponse(t *testing.T) {
	graph := map[string]any{
		"schemaVersion": 2,
		"shell":         "CyShell Desktop",
		"desktop":       map[string]any{"activeWindow": "Editor"},
		"permissions":   []any{map[string]any{"id": "desktop.read", "enabled": true}},
		"capabilities":  map[string]any{"semanticShell": true},
	}
	first, err := finalizeDesktopContext(graph, "", nil)
	if err != nil {
		t.Fatal(err)
	}
	digest, _ := first["contextDigest"].(string)
	if digest == "" {
		t.Fatal("missing context digest")
	}
	second, err := finalizeDesktopContext(graph, digest, nil)
	if err != nil {
		t.Fatal(err)
	}
	if second["unchanged"] != true || second["contextDigest"] != digest {
		t.Fatalf("unexpected unchanged response: %#v", second)
	}
	if _, exists := second["desktop"]; exists {
		t.Fatalf("unchanged response should not repeat desktop payload: %#v", second)
	}
}

func TestFinalizeDesktopContextOmitsKnownUnchangedSections(t *testing.T) {
	graph := map[string]any{
		"schemaVersion": 2,
		"shell":         "CyShell Desktop",
		"desktop":       map[string]any{"activeWindow": "Editor"},
		"permissions":   []any{map[string]any{"id": "desktop.read", "enabled": true}},
		"capabilities":  map[string]any{"semanticShell": true},
	}
	first, err := finalizeDesktopContext(graph, "", nil)
	if err != nil {
		t.Fatal(err)
	}
	sections := first["sectionDigests"].(map[string]string)
	known := map[string]string{
		"permissions":  sections["permissions"],
		"capabilities": sections["capabilities"],
	}
	graph["desktop"] = map[string]any{"activeWindow": "Browser"}
	second, err := finalizeDesktopContext(graph, first["contextDigest"].(string), known)
	if err != nil {
		t.Fatal(err)
	}
	if second["unchanged"] != false {
		t.Fatalf("changed context reported unchanged: %#v", second)
	}
	if _, exists := second["permissions"]; exists {
		t.Fatalf("known permission section should be omitted: %#v", second)
	}
	if _, exists := second["capabilities"]; exists {
		t.Fatalf("known capabilities section should be omitted: %#v", second)
	}
	if _, exists := second["desktop"]; !exists {
		t.Fatalf("changed desktop section must be returned: %#v", second)
	}
}

func TestStableJSONDigestIgnoresMapInsertionOrder(t *testing.T) {
	a := map[string]any{"a": 1, "b": map[string]any{"x": true, "y": "yes"}}
	b := map[string]any{"b": map[string]any{"y": "yes", "x": true}, "a": 1}
	da, err := stableJSONDigest(a)
	if err != nil {
		t.Fatal(err)
	}
	db, err := stableJSONDigest(b)
	if err != nil {
		t.Fatal(err)
	}
	if da != db {
		t.Fatalf("stable digest differs: %q != %q", da, db)
	}
}

func TestDeviceControlPermissionProtectsDesktopUndo(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if err := manager.SetPermission("device.control", false); err != nil {
		t.Fatal(err)
	}
	gate := runtimeGate{manager: manager}
	raw := json.RawMessage(`{"receipt":"action-1","reason":"rollback test"}`)
	if err := gate.BeforeCall(t.Context(), "desktop_undo", raw); err == nil {
		t.Fatal("desktop_undo should require device.control")
	}
}

func TestDesktopReceiptsRequiresDesktopRead(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if err := manager.SetPermission("desktop.read", false); err != nil {
		t.Fatal(err)
	}
	gate := runtimeGate{manager: manager}
	raw := json.RawMessage(`{"reason":"inspect undo receipts"}`)
	if err := gate.BeforeCall(t.Context(), "desktop_receipts", raw); err == nil {
		t.Fatal("desktop_receipts should require desktop.read")
	}
}

func TestSettingsSearchRequiresSettingsRead(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if err := manager.SetPermission("settings.read", false); err != nil {
		t.Fatal(err)
	}
	gate := runtimeGate{manager: manager}
	raw := json.RawMessage(`{"query":"blur","reason":"find the blur setting"}`)
	if err := gate.BeforeCall(t.Context(), "shell_settings_search", raw); err == nil {
		t.Fatal("shell_settings_search should require settings.read")
	}
}

func TestSettingsUndoReceiptRequiresSettingsWrite(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	receipt := manager.issueSettingReceipt("blurEnabled", "false", "true")
	if err := manager.SetPermission("settings.write", false); err != nil {
		t.Fatal(err)
	}
	gate := runtimeGate{manager: manager}
	raw := json.RawMessage(fmt.Sprintf(`{"receipt":%q,"reason":"undo setting"}`, receipt.ID))
	err = gate.BeforeCall(t.Context(), "desktop_undo", raw)
	if err == nil || !strings.Contains(err.Error(), "settings.write") {
		t.Fatalf("setting rollback should require settings.write, got %v", err)
	}
}

func TestDesktopReceiptsWithSettingReceiptRequiresSettingsRead(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	manager.issueSettingReceipt("weatherLocation", "Rayong", "Bangkok")
	if err := manager.SetPermission("settings.read", false); err != nil {
		t.Fatal(err)
	}
	gate := runtimeGate{manager: manager}
	raw := json.RawMessage(`{"reason":"inspect undo receipts"}`)
	err = gate.BeforeCall(t.Context(), "desktop_receipts", raw)
	if err == nil || !strings.Contains(err.Error(), "settings.read") {
		t.Fatalf("setting receipts should require settings.read, got %v", err)
	}
}

func TestApplicationToolsUseDesktopScopes(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	gate := runtimeGate{manager: manager}
	searchArgs := json.RawMessage(`{"query":"browser","reason":"find installed browser"}`)
	launchArgs := json.RawMessage(`{"desktop_id":"example.desktop","reason":"open installed app"}`)

	if err := manager.SetPermission("desktop.read", false); err != nil {
		t.Fatal(err)
	}
	if err := gate.BeforeCall(t.Context(), "application_search", searchArgs); err == nil || !strings.Contains(err.Error(), "desktop.read") {
		t.Fatalf("application_search should require desktop.read, got %v", err)
	}
	if err := manager.SetPermission("desktop.read", true); err != nil {
		t.Fatal(err)
	}
	if err := manager.SetPermission("desktop.control", false); err != nil {
		t.Fatal(err)
	}
	if err := gate.BeforeCall(t.Context(), "application_launch", launchArgs); err == nil || !strings.Contains(err.Error(), "desktop.control") {
		t.Fatalf("application_launch should require desktop.control, got %v", err)
	}
}
