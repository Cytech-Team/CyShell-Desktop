package cycom

import (
	"testing"
	"time"
)

func machineStateFixture() map[string]any {
	return map[string]any{
		"machine": map[string]any{
			"network": map[string]any{
				"wifi": map[string]any{"enabled": true},
			},
			"bluetooth": map[string]any{"enabled": false},
			"audio": map[string]any{
				"output": map[string]any{"volume": float64(67), "muted": true},
				"input":  map[string]any{"volume": float64(42), "muted": false},
			},
			"brightness":   map[string]any{"level": float64(81)},
			"powerProfile": map[string]any{"profile": "balanced"},
		},
	}
}

func TestDesktopUndoFromMachineState(t *testing.T) {
	state := machineStateFixture()
	tests := []struct {
		action     string
		undoAction string
		undoValue  string
	}{
		{"wifi.disable", "wifi.enable", ""},
		{"bluetooth.enable", "bluetooth.disable", ""},
		{"audio.volume.set", "audio.volume.set", "67"},
		{"audio.mute.toggle", "audio.mute.set", "true"},
		{"audio.mute.set", "audio.mute.set", "true"},
		{"mic.volume.set", "mic.volume.set", "42"},
		{"mic.mute.toggle", "mic.mute.set", "false"},
		{"brightness.set", "brightness.set", "81"},
		{"power.profile.set", "power.profile.set", "balanced"},
	}
	for _, tt := range tests {
		t.Run(tt.action, func(t *testing.T) {
			action, value, ok := desktopUndoFromState(tt.action, state)
			if !ok || action != tt.undoAction || value != tt.undoValue {
				t.Fatalf("undo = (%q,%q,%v), want (%q,%q,true)", action, value, ok, tt.undoAction, tt.undoValue)
			}
		})
	}
}

func TestActionReceiptLifecycle(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	receipt := manager.issueActionReceipt("brightness.set", "20", "brightness.set", "80")
	if !receipt.CanUndo || receipt.ID == "" || receipt.ExpiresAt <= receipt.CreatedAt {
		t.Fatalf("invalid receipt: %#v", receipt)
	}
	listed := manager.ActionReceipts()
	if len(listed) != 1 || listed[0].ID != receipt.ID {
		t.Fatalf("receipt not listed: %#v", listed)
	}
	record, err := manager.actionReceiptForUndo(receipt.ID)
	if err != nil {
		t.Fatal(err)
	}
	if record.UndoAction != "brightness.set" || record.UndoValue != "80" {
		t.Fatalf("unexpected undo record: %#v", record)
	}
	manager.consumeActionReceipt(receipt.ID)
	if len(manager.ActionReceipts()) != 0 {
		t.Fatal("consumed receipt still listed")
	}
	if _, err := manager.actionReceiptForUndo(receipt.ID); err == nil {
		t.Fatal("consumed receipt should not be reusable")
	}
}

func TestExpiredActionReceiptIsPruned(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	receipt := manager.issueActionReceipt("wifi.disable", "", "wifi.enable", "")
	manager.receiptsMu.Lock()
	record := manager.actionReceipts[receipt.ID]
	record.Receipt.ExpiresAt = time.Now().Add(-time.Second).UnixMilli()
	manager.actionReceipts[receipt.ID] = record
	manager.receiptsMu.Unlock()
	if got := manager.ActionReceipts(); len(got) != 0 {
		t.Fatalf("expired receipts not pruned: %#v", got)
	}
}

func TestReceiptStateAndSnapshotExposeLiveUndoList(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	receipt := manager.issueActionReceipt("audio.volume.set", "20", "audio.volume.set", "70")
	if got := manager.RuntimeState().UndoReceiptCount; got != 1 {
		t.Fatalf("UndoReceiptCount = %d, want 1", got)
	}
	event := manager.SnapshotEvent()
	if event.ActionReceipts == nil || len(*event.ActionReceipts) != 1 || (*event.ActionReceipts)[0].ID != receipt.ID {
		t.Fatalf("snapshot missing action receipt: %#v", event)
	}
	manager.consumeActionReceipt(receipt.ID)
	if got := manager.RuntimeState().UndoReceiptCount; got != 0 {
		t.Fatalf("UndoReceiptCount after consume = %d, want 0", got)
	}
	event = manager.SnapshotEvent()
	if event.ActionReceipts == nil || len(*event.ActionReceipts) != 0 {
		t.Fatalf("snapshot should carry explicit empty receipt list: %#v", event)
	}
}

func TestSettingReceiptCarriesTargetAndUndoState(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	receipt := manager.issueSettingReceipt("blurEnabled", "false", "true")
	if receipt.Kind != "setting" || receipt.Action != "settings.set" || receipt.Target != "blurEnabled" || receipt.Value != "false" || !receipt.CanUndo {
		t.Fatalf("unexpected setting receipt: %#v", receipt)
	}
	record, err := manager.actionReceiptForUndo(receipt.ID)
	if err != nil {
		t.Fatal(err)
	}
	if record.UndoKind != "setting" || record.UndoAction != "blurEnabled" || record.UndoValue != "true" {
		t.Fatalf("unexpected setting undo record: %#v", record)
	}
}

func TestScalarSettingValueString(t *testing.T) {
	tests := []struct {
		value any
		want  string
		ok    bool
	}{
		{true, "true", true},
		{false, "false", true},
		{"hello", "hello", true},
		{float64(42), "42", true},
		{float64(3.5), "3.5", true},
		{[]any{"not", "scalar"}, "", false},
	}
	for _, tt := range tests {
		got, ok := scalarSettingValueString(tt.value)
		if got != tt.want || ok != tt.ok {
			t.Fatalf("scalarSettingValueString(%#v) = (%q,%v), want (%q,%v)", tt.value, got, ok, tt.want, tt.ok)
		}
	}
}
