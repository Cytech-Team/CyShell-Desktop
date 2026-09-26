package cycom

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/AvengeMedia/dankgo/ipc"
)

func receiveAgentEvent(t *testing.T, ch <-chan Event) Event {
	t.Helper()
	select {
	case event := <-ch:
		return event
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for Agent event")
		return Event{}
	}
}

func receiveAgentEventKind(t *testing.T, ch <-chan Event, kind string) Event {
	t.Helper()
	deadline := time.After(2 * time.Second)
	for {
		select {
		case event := <-ch:
			if event.Kind == kind {
				return event
			}
		case <-deadline:
			t.Fatalf("timed out waiting for Agent %s event", kind)
			return Event{}
		}
	}
}

func TestAgentActivityEmitsRunningAndSucceeded(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	ch := manager.Subscribe("activity-test")
	defer manager.Unsubscribe("activity-test")

	_, err = manager.Call(context.Background(), "system_info", json.RawMessage(`{"reason":"inspect the local system"}`))
	if err != nil {
		t.Fatal(err)
	}
	running := receiveAgentEventKind(t, ch, "activity")
	finished := receiveAgentEventKind(t, ch, "activity")
	if running.Kind != "activity" || running.Activity == nil || running.Activity.Status != "running" {
		t.Fatalf("unexpected running event: %#v", running)
	}
	if running.Activity.Tool != "system_info" || running.Activity.Reason != "inspect the local system" {
		t.Fatalf("unexpected running activity: %#v", running.Activity)
	}
	if finished.Kind != "activity" || finished.Activity == nil || finished.Activity.Status != "succeeded" {
		t.Fatalf("unexpected finished event: %#v", finished)
	}
	if finished.Activity.ID != running.Activity.ID || finished.State == nil || finished.State.ActiveCalls != 0 {
		t.Fatalf("activity lifecycle did not close cleanly: running=%#v finished=%#v", running, finished)
	}
	if len(manager.RecentActivity()) != 1 || manager.RecentActivity()[0].Status != "succeeded" {
		t.Fatalf("recent activity not updated: %#v", manager.RecentActivity())
	}
}

func TestAgentStateBroadcastsPermissionChanges(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	ch := manager.Subscribe("state-test")
	defer manager.Unsubscribe("state-test")
	if err := manager.SetPermission("files.write", false); err != nil {
		t.Fatal(err)
	}
	event := receiveAgentEvent(t, ch)
	if event.Kind != "state" || event.State == nil {
		t.Fatalf("unexpected state event: %#v", event)
	}
	found := false
	for _, permission := range event.State.Permissions {
		if permission.ID == "files.write" {
			found = true
			if permission.Enabled {
				t.Fatal("files.write should be disabled in broadcast state")
			}
		}
	}
	if !found {
		t.Fatal("files.write missing from broadcast permission state")
	}
}

func TestAgentSnapshotContainsRecentActivity(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := manager.Call(context.Background(), "system_info", json.RawMessage(`{"reason":"snapshot test"}`)); err != nil {
		t.Fatal(err)
	}
	event := manager.SnapshotEvent()
	if event.Kind != "snapshot" || event.State == nil || event.RecentActivity == nil || len(*event.RecentActivity) != 1 {
		t.Fatalf("unexpected snapshot: %#v", event)
	}
	if (*event.RecentActivity)[0].Reason != "snapshot test" || (*event.RecentActivity)[0].Status != "succeeded" {
		t.Fatalf("unexpected snapshot activity: %#v", (*event.RecentActivity)[0])
	}
}

func TestClearRecentActivityBroadcastsExplicitEmptyList(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := manager.Call(context.Background(), "system_info", json.RawMessage(`{"reason":"clear me"}`)); err != nil {
		t.Fatal(err)
	}
	ch := manager.Subscribe("activity-clear")
	defer manager.Unsubscribe("activity-clear")
	manager.ClearRecentActivity()
	event := receiveAgentEventKind(t, ch, "activity_reset")
	if event.RecentActivity == nil || len(*event.RecentActivity) != 0 {
		t.Fatalf("clear event must carry an explicit empty recentActivity list: %#v", event)
	}
	data, err := json.Marshal(event)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), `"recentActivity":[]`) {
		t.Fatalf("clear event JSON omitted the empty list: %s", data)
	}
}

func TestAgentActivityPreservesCallOrigin(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	_, err = manager.CallWithOrigin(context.Background(), "system_info", json.RawMessage(`{"reason":"origin test"}`), CallOrigin{
		Kind:    "mcp",
		Name:    "Claude Desktop",
		Version: "9.9",
	})
	if err != nil {
		t.Fatal(err)
	}
	activity := manager.RecentActivity()
	if len(activity) != 1 {
		t.Fatalf("activity count = %d, want 1", len(activity))
	}
	origin := activity[0].Origin
	if origin.Kind != "mcp" || origin.Name != "Claude Desktop" || origin.Version != "9.9" {
		t.Fatalf("unexpected origin: %#v", origin)
	}
}

func TestNormalizeCallOriginDoesNotTrustBlankLabels(t *testing.T) {
	origin := normalizeCallOrigin(CallOrigin{Kind: "mcp", Name: "   ", Version: " 1.0  beta "})
	if origin.Kind != "mcp" || origin.Name != "External MCP client" || origin.Version != "1.0 beta" {
		t.Fatalf("unexpected normalized origin: %#v", origin)
	}
}

func TestCallOriginFromIPCRequest(t *testing.T) {
	req := ipc.Request{Params: map[string]any{
		"origin": map[string]any{
			"kind":    "mcp",
			"name":    "Codex",
			"version": "1.2.3",
		},
	}}
	origin := callOriginFromRequest(req)
	if origin.Kind != "mcp" || origin.Name != "Codex" || origin.Version != "1.2.3" {
		t.Fatalf("unexpected IPC origin: %#v", origin)
	}
}
