package cycom

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
)

func TestAnthropicNativeToolRoundTrip(t *testing.T) {
	var turns atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/messages" {
			http.NotFound(w, r)
			return
		}
		if got := r.Header.Get("x-api-key"); got != "anthropic-test-key" {
			t.Fatalf("x-api-key = %q", got)
		}
		if got := r.Header.Get("anthropic-version"); got == "" {
			t.Fatal("missing anthropic-version header")
		}
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		turn := turns.Add(1)
		if turn == 1 {
			_ = json.NewEncoder(w).Encode(map[string]any{
				"content": []any{map[string]any{
					"type":  "tool_use",
					"id":    "toolu_system_info",
					"name":  "system_info",
					"input": map[string]any{},
				}},
				"stop_reason": "tool_use",
			})
			return
		}
		messages, _ := body["messages"].([]any)
		encoded, _ := json.Marshal(messages)
		if !strings.Contains(string(encoded), `"type":"tool_result"`) || !strings.Contains(string(encoded), `"tool_use_id":"toolu_system_info"`) {
			t.Fatalf("second Anthropic request missing tool_result: %s", encoded)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"content":     []any{map[string]any{"type": "text", "text": "anthropic done"}},
			"stop_reason": "end_turn",
		})
	}))
	defer server.Close()

	t.Setenv("XDG_STATE_HOME", t.TempDir())
	t.Setenv("CYSHELL_AGENT_PROVIDER", "anthropic")
	t.Setenv("CYSHELL_AGENT_BASE_URL", server.URL)
	t.Setenv("CYSHELL_AGENT_MODEL", "claude-test")
	t.Setenv("CYSHELL_AGENT_API_KEY", "anthropic-test-key")
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	result, err := manager.assistant.Chat(context.Background(), "inspect the system")
	if err != nil {
		t.Fatal(err)
	}
	if result.Message != "anthropic done" || len(result.ToolCalls) != 1 || result.ToolCalls[0] != "system_info" {
		t.Fatalf("unexpected Anthropic result: %#v", result)
	}
}

func TestGeminiNativeReplaysThoughtSignatureAndFunctionID(t *testing.T) {
	var turns atomic.Int32
	const signature = "opaque-thought-signature"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1beta/models/gemini-test:generateContent" {
			http.NotFound(w, r)
			return
		}
		if got := r.Header.Get("x-goog-api-key"); got != "gemini-test-key" {
			t.Fatalf("x-goog-api-key = %q", got)
		}
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		turn := turns.Add(1)
		if turn == 1 {
			_ = json.NewEncoder(w).Encode(map[string]any{
				"candidates": []any{map[string]any{
					"content": map[string]any{
						"role": "model",
						"parts": []any{map[string]any{
							"functionCall": map[string]any{
								"id":   "gemini-system-info-1",
								"name": "system_info",
								"args": map[string]any{},
							},
							"thoughtSignature": signature,
						}},
					},
				}},
			})
			return
		}
		contents, _ := body["contents"].([]any)
		encoded, _ := json.Marshal(contents)
		text := string(encoded)
		if !strings.Contains(text, signature) {
			t.Fatalf("Gemini thought signature was not replayed: %s", text)
		}
		if !strings.Contains(text, `"functionResponse":{"id":"gemini-system-info-1"`) {
			t.Fatalf("Gemini function response did not preserve function id: %s", text)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"candidates": []any{map[string]any{
				"content": map[string]any{
					"role":  "model",
					"parts": []any{map[string]any{"text": "gemini done"}},
				},
			}},
		})
	}))
	defer server.Close()

	t.Setenv("XDG_STATE_HOME", t.TempDir())
	t.Setenv("CYSHELL_AGENT_PROVIDER", "gemini")
	t.Setenv("CYSHELL_AGENT_BASE_URL", server.URL+"/v1beta")
	t.Setenv("CYSHELL_AGENT_MODEL", "gemini-test")
	t.Setenv("CYSHELL_AGENT_API_KEY", "gemini-test-key")
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	result, err := manager.assistant.Chat(context.Background(), "inspect the system")
	if err != nil {
		t.Fatal(err)
	}
	if result.Message != "gemini done" || len(result.ToolCalls) != 1 || result.ToolCalls[0] != "system_info" {
		t.Fatalf("unexpected Gemini result: %#v", result)
	}
}

func TestAssistantHistoryPersistsAcrossManagerRestart(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" {
			http.NotFound(w, r)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"choices": []any{map[string]any{
				"message": map[string]any{"role": "assistant", "content": "remembered answer"},
			}},
		})
	}))
	defer server.Close()

	stateHome := t.TempDir()
	t.Setenv("XDG_STATE_HOME", stateHome)
	t.Setenv("CYSHELL_AGENT_PROVIDER", "openai-compatible")
	t.Setenv("CYSHELL_AGENT_BASE_URL", server.URL+"/v1")
	t.Setenv("CYSHELL_AGENT_MODEL", "test-model")
	first, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := first.assistant.Chat(context.Background(), "remember this"); err != nil {
		t.Fatal(err)
	}

	second, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	history := second.assistant.History()
	if len(history) != 2 || history[0].Content != "remember this" || history[1].Content != "remembered answer" {
		t.Fatalf("unexpected reloaded history: %#v", history)
	}
	second.assistant.Clear()
	third, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	if got := third.assistant.History(); len(got) != 0 {
		t.Fatalf("cleared history reappeared after restart: %#v", got)
	}
}
