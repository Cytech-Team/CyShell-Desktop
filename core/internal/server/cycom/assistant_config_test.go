package cycom

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNormalizeAssistantEndpoint(t *testing.T) {
	got, err := normalizeAssistantEndpoint(" http://127.0.0.1:11434/v1/ ")
	if err != nil {
		t.Fatal(err)
	}
	if got != "http://127.0.0.1:11434/v1" {
		t.Fatalf("endpoint = %q", got)
	}
	if _, err := normalizeAssistantEndpoint("file:///tmp/model"); err == nil {
		t.Fatal("expected non-http endpoint to be rejected")
	}
}

func TestAssistantConfigNeverPersistsAPIKey(t *testing.T) {
	path := filepath.Join(t.TempDir(), "assistant.json")
	a := &Assistant{
		baseURL:    "https://example.invalid/v1",
		model:      "test-model",
		configPath: path,
		apiKey:     "must-not-be-written",
		hasAPIKey:  true,
		keySource:  "keyring",
	}
	if err := a.persistConfig(); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	if strings.Contains(text, "must-not-be-written") {
		t.Fatal("assistant API key leaked into config file")
	}
	if !strings.Contains(text, "test-model") || !strings.Contains(text, "https://example.invalid/v1") {
		t.Fatalf("unexpected config: %s", text)
	}
}

func TestAssistantProviderProfilesPersist(t *testing.T) {
	stateHome := t.TempDir()
	t.Setenv("XDG_STATE_HOME", stateHome)
	manager, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	assistant := manager.assistant
	assistant.mu.Lock()
	assistant.provider = "openai-compatible"
	assistant.baseURL = "http://127.0.0.1:11434/v1"
	assistant.model = "local-model"
	assistant.profiles["openai-compatible"] = AssistantProviderProfile{Endpoint: assistant.baseURL, Model: assistant.model}
	assistant.profiles["anthropic"] = AssistantProviderProfile{Endpoint: "https://api.anthropic.com", Model: "claude-test"}
	if err := assistant.persistConfig(); err != nil {
		assistant.mu.Unlock()
		t.Fatal(err)
	}
	assistant.mu.Unlock()

	reloaded, err := NewManager()
	if err != nil {
		t.Fatal(err)
	}
	state := reloaded.assistant.State()
	if got := state.Profiles["anthropic"]; got.Model != "claude-test" || got.Endpoint != "https://api.anthropic.com" {
		t.Fatalf("anthropic profile did not persist: %#v", got)
	}
	if got := state.Profiles["openai-compatible"]; got.Model != "local-model" {
		t.Fatalf("openai profile did not persist: %#v", got)
	}
}
