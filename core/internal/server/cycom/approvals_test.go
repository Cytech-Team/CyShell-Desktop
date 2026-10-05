package cycom

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func waitForApproval(t *testing.T, manager *Manager) ApprovalRequest {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		items := manager.PendingApprovals()
		if len(items) == 1 {
			return items[0]
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatal("approval request did not appear")
	return ApprovalRequest{}
}

func TestPerAppApprovalAllowOnce(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	gate := runtimeGate{manager: manager}
	raw := json.RawMessage(`{"app_id":"org.example.Editor","reason":"read the visible editor UI","include_screenshot":false}`)

	result := make(chan error, 1)
	go func() {
		result <- gate.BeforeCall(context.Background(), "anyapp_get_app_state", raw)
	}()
	approval := waitForApproval(t, manager)
	if approval.AppKey != "app:org.example.editor" || approval.AppName != "org.example.Editor" {
		t.Fatalf("unexpected approval target: %#v", approval)
	}
	if len(approval.Scopes) != 1 || approval.Scopes[0] != "app.read" {
		t.Fatalf("unexpected scopes: %#v", approval.Scopes)
	}
	if err := manager.RespondApproval(approval.ID, "allow_once"); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-result:
		if err != nil {
			t.Fatalf("allow-once gate failed: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("allow-once approval did not unblock the tool call")
	}
	if len(manager.AppPolicies()) != 0 {
		t.Fatalf("allow_once must not persist an app policy: %#v", manager.AppPolicies())
	}
}

func TestPerAppApprovalAllowAlwaysPersists(t *testing.T) {
	stateHome := t.TempDir()
	t.Setenv("XDG_STATE_HOME", stateHome)
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	gate := runtimeGate{manager: manager}
	raw := json.RawMessage(`{"app_id":"org.example.Chat","reason":"inspect chat controls","include_screenshot":false}`)

	result := make(chan error, 1)
	go func() { result <- gate.BeforeCall(context.Background(), "anyapp_get_app_state", raw) }()
	approval := waitForApproval(t, manager)
	if !approval.CanRemember {
		t.Fatal("stable app id should allow persistent approval")
	}
	if err := manager.RespondApproval(approval.ID, "allow_always"); err != nil {
		t.Fatal(err)
	}
	if err := <-result; err != nil {
		t.Fatal(err)
	}

	reloaded, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if got := reloaded.appPolicyMode("app:org.example.chat", "app.read"); got != "allow" {
		t.Fatalf("persisted app.read policy = %q, want allow", got)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	if err := (runtimeGate{manager: reloaded}).BeforeCall(ctx, "anyapp_get_app_state", raw); err != nil {
		t.Fatalf("persistent allow should not ask again: %v", err)
	}
}

func TestPerAppDenyPolicyBlocksWithoutApproval(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if err := manager.SetAppPolicy("app:org.example.chat", "Example Chat", "app.control", "deny"); err != nil {
		t.Fatal(err)
	}
	raw := json.RawMessage(`{"app_id":"org.example.Chat","reason":"click send","index":4}`)
	if err := (runtimeGate{manager: manager}).BeforeCall(context.Background(), "anyapp_click", raw); err == nil {
		t.Fatal("deny policy should block app.control")
	}
	if got := len(manager.PendingApprovals()); got != 0 {
		t.Fatalf("deny policy should not create approval, got %d", got)
	}
}

func TestApprovalLifecycleBroadcastsPendingState(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	ch := manager.Subscribe("approval-events")
	defer manager.Unsubscribe("approval-events")
	gate := runtimeGate{manager: manager}
	raw := json.RawMessage(`{"app_id":"org.example.Editor","reason":"inspect editor controls","include_screenshot":false}`)

	result := make(chan error, 1)
	go func() { result <- gate.BeforeCall(context.Background(), "anyapp_get_app_state", raw) }()
	pendingEvent := receiveAgentEvent(t, ch)
	if pendingEvent.Kind != "state" || pendingEvent.State == nil || pendingEvent.State.PendingApprovalCount != 1 || pendingEvent.PendingApprovals == nil || len(*pendingEvent.PendingApprovals) != 1 {
		t.Fatalf("unexpected pending approval event: %#v", pendingEvent)
	}
	if err := manager.RespondApproval((*pendingEvent.PendingApprovals)[0].ID, "allow_once"); err != nil {
		t.Fatal(err)
	}
	if err := <-result; err != nil {
		t.Fatal(err)
	}
	clearedEvent := receiveAgentEvent(t, ch)
	if clearedEvent.Kind != "state" || clearedEvent.State == nil || clearedEvent.State.PendingApprovalCount != 0 || clearedEvent.PendingApprovals == nil || len(*clearedEvent.PendingApprovals) != 0 {
		t.Fatalf("approval cleanup was not broadcast: %#v", clearedEvent)
	}
	encoded, err := json.Marshal(clearedEvent)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(encoded), `"pendingApprovals":[]`) {
		t.Fatalf("approval cleanup JSON omitted explicit empty queue: %s", encoded)
	}
}

func TestPerAppApprovalAllowSessionStopsRepeatedPrompts(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	gate := runtimeGate{manager: manager}
	raw := json.RawMessage(`{"app_id":"org.example.Editor","reason":"inspect editor","include_screenshot":false}`)

	first := make(chan error, 1)
	go func() { first <- gate.BeforeCall(context.Background(), "anyapp_get_app_state", raw) }()
	approval := waitForApproval(t, manager)
	if err := manager.RespondApproval(approval.ID, "allow_session"); err != nil {
		t.Fatal(err)
	}
	if err := <-first; err != nil {
		t.Fatalf("session approval failed: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	if err := gate.BeforeCall(ctx, "anyapp_get_app_state", raw); err != nil {
		t.Fatalf("same app capability should be allowed for the session without another prompt: %v", err)
	}
	if got := len(manager.PendingApprovals()); got != 0 {
		t.Fatalf("session grant should suppress repeated prompt, got %d pending", got)
	}
	if len(manager.AppPolicies()) != 0 {
		t.Fatalf("session grant must not become a persistent policy: %#v", manager.AppPolicies())
	}
}

func TestApprovalModeAutoApprovesReadButAsksForControl(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if err := manager.SetApprovalMode("auto"); err != nil {
		t.Fatal(err)
	}
	gate := runtimeGate{manager: manager}

	readRaw := json.RawMessage(`{"app_id":"org.example.Chat","reason":"inspect chat controls","include_screenshot":true}`)
	if err := gate.BeforeCall(context.Background(), "anyapp_get_app_state", readRaw); err != nil {
		t.Fatalf("auto mode should approve read/screen capture without prompting: %v", err)
	}
	if got := len(manager.PendingApprovals()); got != 0 {
		t.Fatalf("auto read should not create approval prompts, got %d", got)
	}

	controlRaw := json.RawMessage(`{"app_id":"org.example.Chat","reason":"click send","index":4}`)
	result := make(chan error, 1)
	go func() { result <- gate.BeforeCall(context.Background(), "anyapp_click", controlRaw) }()
	approval := waitForApproval(t, manager)
	if len(approval.Scopes) != 1 || approval.Scopes[0] != "app.control" {
		t.Fatalf("auto mode should only ask for app.control here, got %#v", approval.Scopes)
	}
	if err := manager.RespondApproval(approval.ID, "deny_once"); err != nil {
		t.Fatal(err)
	}
	if err := <-result; err == nil {
		t.Fatal("denied auto-mode control request should fail")
	}

	fileResult := make(chan error, 1)
	fileRaw := json.RawMessage(`{"path":"/tmp/example.txt","reason":"replace a local file"}`)
	go func() { fileResult <- gate.BeforeCall(context.Background(), "fs_write", fileRaw) }()
	fileApproval := waitForApproval(t, manager)
	if len(fileApproval.Scopes) != 1 || fileApproval.Scopes[0] != "files.write" {
		t.Fatalf("auto mode should ask for files.write, got %#v", fileApproval.Scopes)
	}
	if err := manager.RespondApproval(fileApproval.ID, "deny_once"); err != nil {
		t.Fatal(err)
	}
	if err := <-fileResult; err == nil {
		t.Fatal("denied auto-mode file write should fail")
	}
}

func TestApprovalModeCustomUsesSavedRulesAndPromptsUnknown(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if err := manager.SetApprovalMode("custom"); err != nil {
		t.Fatal(err)
	}
	if err := manager.SetAppPolicy("app:org.example.chat", "Example Chat", "app.read", "allow"); err != nil {
		t.Fatal(err)
	}
	gate := runtimeGate{manager: manager}
	readRaw := json.RawMessage(`{"app_id":"org.example.Chat","reason":"inspect chat","include_screenshot":false}`)
	if err := gate.BeforeCall(context.Background(), "anyapp_get_app_state", readRaw); err != nil {
		t.Fatalf("custom saved allow rule should pass: %v", err)
	}

	controlRaw := json.RawMessage(`{"app_id":"org.example.Chat","reason":"click send","index":4}`)
	result := make(chan error, 1)
	go func() { result <- gate.BeforeCall(context.Background(), "anyapp_click", controlRaw) }()
	approval := waitForApproval(t, manager)
	if len(approval.Scopes) != 1 || approval.Scopes[0] != "app.control" {
		t.Fatalf("custom unknown control should ask, got %#v", approval.Scopes)
	}
	if err := manager.RespondApproval(approval.ID, "allow_once"); err != nil {
		t.Fatal(err)
	}
	if err := <-result; err != nil {
		t.Fatalf("custom allow-once should unblock: %v", err)
	}
}

func TestApprovalModeFullBypassesNormalPermissionGates(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if err := manager.SetPermission("app.control", false); err != nil {
		t.Fatal(err)
	}
	manager.controlEnabled.Store(false)
	if err := manager.SetAppPolicy("app:org.example.chat", "Example Chat", "app.control", "deny"); err != nil {
		t.Fatal(err)
	}
	if err := manager.SetApprovalMode("full"); err != nil {
		t.Fatal(err)
	}

	gate := runtimeGate{manager: manager}
	controlRaw := json.RawMessage(`{"app_id":"org.example.Chat","reason":"click send","index":4}`)
	if err := gate.BeforeCall(context.Background(), "anyapp_click", controlRaw); err != nil {
		t.Fatalf("full access should bypass scope/master/per-app gates: %v", err)
	}
	if got := len(manager.PendingApprovals()); got != 0 {
		t.Fatalf("full access should not create approval prompts, got %d", got)
	}

	manager.enabled.Store(false)
	if err := gate.BeforeCall(context.Background(), "anyapp_click", controlRaw); err == nil || !strings.Contains(err.Error(), "disabled") {
		t.Fatalf("Agent disabled kill switch must still stop full access, got %v", err)
	}
}

func TestApprovalModePersists(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if err := manager.SetApprovalMode("full"); err != nil {
		t.Fatal(err)
	}

	reloaded, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if got := reloaded.ApprovalMode(); got != "full" {
		t.Fatalf("reloaded approval mode = %q, want full", got)
	}
}
