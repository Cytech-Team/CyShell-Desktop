package cycom

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestAssistantChatTextResponse(t *testing.T) {
	var requests atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" {
			http.NotFound(w, r)
			return
		}
		requests.Add(1)
		var body assistantRequest
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		if body.Model != "test-model" || len(body.Tools) == 0 {
			t.Fatalf("unexpected assistant request: model=%q tools=%d", body.Model, len(body.Tools))
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"choices": []any{map[string]any{
				"message": map[string]any{"role": "assistant", "content": "hello from CyShell"},
			}},
		})
	}))
	defer server.Close()

	t.Setenv("XDG_STATE_HOME", t.TempDir())
	t.Setenv("CYSHELL_AGENT_BASE_URL", server.URL+"/v1")
	t.Setenv("CYSHELL_AGENT_MODEL", "test-model")
	t.Setenv("CYSHELL_AGENT_API_KEY", "super-secret-test-key")
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	result, err := manager.assistant.Chat(context.Background(), "say hello")
	if err != nil {
		t.Fatal(err)
	}
	if result.Message != "hello from CyShell" || result.Model != "test-model" || requests.Load() != 1 {
		t.Fatalf("unexpected result: %#v requests=%d", result, requests.Load())
	}
	stateJSON, err := json.Marshal(manager.State())
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(stateJSON), "super-secret-test-key") {
		t.Fatal("assistant state leaked API key")
	}
}

func TestAssistantToolRoundTripUsesEmbeddedRuntime(t *testing.T) {
	var requests atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" {
			http.NotFound(w, r)
			return
		}
		n := requests.Add(1)
		var body assistantRequest
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		if n == 1 {
			_ = json.NewEncoder(w).Encode(map[string]any{
				"choices": []any{map[string]any{
					"message": map[string]any{
						"role": "assistant",
						"tool_calls": []any{map[string]any{
							"id":   "call_system_info",
							"type": "function",
							"function": map[string]any{
								"name":      "system_info",
								"arguments": `{}`,
							},
						}},
					},
				}},
			})
			return
		}
		foundToolResult := false
		for _, message := range body.Messages {
			if message.Role == "tool" && message.ToolCallID == "call_system_info" && strings.Contains(message.Content, "goos") {
				foundToolResult = true
				break
			}
		}
		if !foundToolResult {
			t.Fatalf("second request did not include CyCom system_info result: %#v", body.Messages)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"choices": []any{map[string]any{
				"message": map[string]any{"role": "assistant", "content": "system inspected"},
			}},
		})
	}))
	defer server.Close()

	t.Setenv("XDG_STATE_HOME", t.TempDir())
	t.Setenv("CYSHELL_AGENT_BASE_URL", server.URL+"/v1")
	t.Setenv("CYSHELL_AGENT_MODEL", "test-model")
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	result, err := manager.assistant.Chat(context.Background(), "inspect the computer")
	if err != nil {
		t.Fatal(err)
	}
	if result.Message != "system inspected" || len(result.ToolCalls) != 1 || result.ToolCalls[0] != "system_info" {
		t.Fatalf("unexpected result: %#v", result)
	}
	if requests.Load() != 2 {
		t.Fatalf("expected two provider turns, got %d", requests.Load())
	}
}

func TestAssistantModelDiscovery(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			_ = json.NewEncoder(w).Encode(map[string]any{"data": []any{map[string]any{"id": "auto-model"}}})
		case "/v1/chat/completions":
			_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"message": map[string]any{"role": "assistant", "content": "auto"}}}})
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	t.Setenv("XDG_STATE_HOME", t.TempDir())
	t.Setenv("CYSHELL_AGENT_BASE_URL", server.URL+"/v1")
	t.Setenv("CYSHELL_AGENT_MODEL", "")
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	result, err := manager.assistant.Chat(context.Background(), "hello")
	if err != nil {
		t.Fatal(err)
	}
	if result.Model != "auto-model" {
		t.Fatalf("model = %q, want auto-model", result.Model)
	}
}

func TestEmergencyStopCancelsInFlightAssistantRequest(t *testing.T) {
	started := make(chan struct{})
	release := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" {
			http.NotFound(w, r)
			return
		}
		close(started)
		select {
		case <-r.Context().Done():
		case <-release:
		}
	}))
	defer func() {
		close(release)
		server.Close()
	}()

	t.Setenv("XDG_STATE_HOME", t.TempDir())
	t.Setenv("CYSHELL_AGENT_BASE_URL", server.URL+"/v1")
	t.Setenv("CYSHELL_AGENT_MODEL", "test-model")
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}

	result := make(chan error, 1)
	go func() {
		_, err := manager.assistant.Chat(context.Background(), "wait")
		result <- err
	}()
	<-started
	if err := manager.EmergencyStop(); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-result:
		if err == nil || !strings.Contains(err.Error(), "context canceled") {
			t.Fatalf("expected canceled assistant request, got %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("assistant request was not canceled by emergency stop")
	}
}
