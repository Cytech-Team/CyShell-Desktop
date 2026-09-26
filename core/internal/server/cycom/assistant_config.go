package cycom

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/secretstore"
)

const assistantSecretSchema = "org.cyshell.Agent"

type assistantConfigFile struct {
	Version  int                                 `json:"version"`
	Provider string                              `json:"provider,omitempty"`
	Endpoint string                              `json:"endpoint"`
	Model    string                              `json:"model,omitempty"`
	Profiles map[string]AssistantProviderProfile `json:"profiles,omitempty"`
}

func assistantConfigPath(manager *Manager) string {
	if manager != nil && manager.runtime != nil && strings.TrimSpace(manager.runtime.StateDir()) != "" {
		return filepath.Join(manager.runtime.StateDir(), "cyshell-assistant.json")
	}
	return filepath.Join(defaultStateDir(), "cyshell-assistant.json")
}

func normalizeAssistantProvider(raw string) (string, bool) {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "openai", "openai-compatible", "ollama", "custom":
		return "openai-compatible", true
	case "anthropic", "claude":
		return "anthropic", true
	case "gemini", "google":
		return "gemini", true
	default:
		return "", false
	}
}

func defaultAssistantEndpoint(provider string) string {
	switch provider {
	case "anthropic":
		return "https://api.anthropic.com"
	case "gemini":
		return "https://generativelanguage.googleapis.com/v1beta"
	default:
		return "http://127.0.0.1:11434/v1"
	}
}

func normalizeAssistantEndpoint(raw string) (string, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return "", errors.New("assistant endpoint is required")
	}
	u, err := url.Parse(raw)
	if err != nil || u.Scheme == "" || u.Host == "" {
		return "", fmt.Errorf("invalid Assistant endpoint %q", raw)
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return "", errors.New("Assistant endpoint must use http or https")
	}
	u.RawQuery = ""
	u.Fragment = ""
	return strings.TrimRight(u.String(), "/"), nil
}

func (a *Assistant) loadConfig() error {
	if a == nil || a.configPath == "" {
		return nil
	}
	data, err := os.ReadFile(a.configPath)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	var cfg assistantConfigFile
	if err := json.Unmarshal(data, &cfg); err != nil {
		return fmt.Errorf("decode Assistant config: %w", err)
	}
	if strings.TrimSpace(cfg.Provider) != "" {
		provider, ok := normalizeAssistantProvider(cfg.Provider)
		if !ok {
			return fmt.Errorf("invalid Assistant provider %q", cfg.Provider)
		}
		a.provider = provider
	}
	if a.profiles == nil {
		a.profiles = make(map[string]AssistantProviderProfile)
	}
	for id, profile := range cfg.Profiles {
		provider, ok := normalizeAssistantProvider(id)
		if !ok {
			continue
		}
		if endpoint, err := normalizeAssistantEndpoint(profile.Endpoint); err == nil {
			a.profiles[provider] = AssistantProviderProfile{Endpoint: endpoint, Model: strings.TrimSpace(profile.Model)}
		}
	}
	if cfg.Endpoint != "" {
		endpoint, err := normalizeAssistantEndpoint(cfg.Endpoint)
		if err != nil {
			return err
		}
		a.baseURL = endpoint
	}
	a.model = strings.TrimSpace(cfg.Model)
	return nil
}

func (a *Assistant) persistConfig() error {
	if a == nil || a.configPath == "" {
		return errors.New("Assistant config path is unavailable")
	}
	if err := os.MkdirAll(filepath.Dir(a.configPath), 0o700); err != nil {
		return err
	}
	profiles := make(map[string]AssistantProviderProfile, len(a.profiles)+1)
	for id, profile := range a.profiles {
		profiles[id] = profile
	}
	profiles[a.provider] = AssistantProviderProfile{Endpoint: a.baseURL, Model: a.model}
	data, err := json.MarshalIndent(assistantConfigFile{
		Version:  3,
		Provider: a.provider,
		Endpoint: a.baseURL,
		Model:    a.model,
		Profiles: profiles,
	}, "", "  ")
	if err != nil {
		return err
	}
	tmp := a.configPath + ".tmp"
	if err := os.WriteFile(tmp, append(data, '\n'), 0o600); err != nil {
		return err
	}
	if err := os.Chmod(tmp, 0o600); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, a.configPath)
}

func assistantSecretAttributes(provider, endpoint string) map[string]string {
	return map[string]string{
		"xdg:schema": assistantSecretSchema,
		"kind":       "provider-api-key",
		"provider":   provider,
		"endpoint":   endpoint,
	}
}

func legacyAssistantSecretAttributes(endpoint string) map[string]string {
	return map[string]string{
		"xdg:schema": assistantSecretSchema,
		"kind":       "provider-api-key",
		"endpoint":   endpoint,
	}
}

func (a *Assistant) refreshKeyPresence(provider, endpoint string) {
	if a == nil {
		return
	}
	if a.envAPIKey {
		a.keyMu.Lock()
		a.hasAPIKey = true
		a.keySource = "environment"
		a.keyMu.Unlock()
		return
	}
	store, err := secretstore.Open()
	if err != nil {
		a.keyMu.Lock()
		a.hasAPIKey = false
		a.keySource = ""
		a.keyMu.Unlock()
		return
	}
	defer store.Close()
	exists, err := store.Exists(assistantSecretAttributes(provider, endpoint))
	if err == nil && !exists && provider == "openai-compatible" {
		exists, err = store.Exists(legacyAssistantSecretAttributes(endpoint))
	}
	a.keyMu.Lock()
	defer a.keyMu.Unlock()
	if err != nil {
		a.hasAPIKey = false
		a.keySource = ""
		return
	}
	a.hasAPIKey = exists
	if exists {
		a.keySource = "keyring"
	} else {
		a.keySource = ""
	}
}

func (a *Assistant) providerAPIKey(provider, endpoint string) (string, error) {
	if a == nil {
		return "", nil
	}
	a.keyMu.Lock()
	if a.apiKeyLoaded {
		key := a.apiKey
		a.keyMu.Unlock()
		return key, nil
	}
	hasKey := a.hasAPIKey
	a.keyMu.Unlock()
	if !hasKey {
		return "", nil
	}

	store, err := secretstore.Open()
	if err != nil {
		return "", fmt.Errorf("open desktop keyring: %w", err)
	}
	defer store.Close()
	key, found, err := store.Get(assistantSecretAttributes(provider, endpoint))
	if err != nil {
		return "", fmt.Errorf("read Assistant API key from desktop keyring: %w", err)
	}
	if !found && provider == "openai-compatible" {
		key, found, err = store.Get(legacyAssistantSecretAttributes(endpoint))
		if err != nil {
			return "", fmt.Errorf("read legacy Assistant API key from desktop keyring: %w", err)
		}
	}
	if !found {
		a.keyMu.Lock()
		a.hasAPIKey = false
		a.keySource = ""
		a.apiKeyLoaded = true
		a.apiKey = ""
		a.keyMu.Unlock()
		return "", nil
	}
	a.keyMu.Lock()
	a.apiKey = key
	a.apiKeyLoaded = true
	a.hasAPIKey = key != ""
	a.keySource = "keyring"
	a.keyMu.Unlock()
	return key, nil
}

func (a *Assistant) Configure(ctx context.Context, provider, endpoint, model, apiKey string, clearKey bool) (AssistantState, error) {
	if a == nil {
		return AssistantState{}, errors.New("CyShell Assistant is unavailable")
	}
	provider = strings.TrimSpace(provider)
	if provider == "" {
		provider = a.provider
	}
	normalizedProvider, ok := normalizeAssistantProvider(provider)
	if !ok {
		return AssistantState{}, fmt.Errorf("invalid Assistant provider %q", provider)
	}
	if strings.TrimSpace(endpoint) == "" {
		endpoint = defaultAssistantEndpoint(normalizedProvider)
	}
	normalized, err := normalizeAssistantEndpoint(endpoint)
	if err != nil {
		return AssistantState{}, err
	}
	if a.envAPIKey && (strings.TrimSpace(apiKey) != "" || clearKey) {
		return AssistantState{}, errors.New("Assistant API key is managed by CYSHELL_AGENT_API_KEY in the environment")
	}

	a.mu.Lock()
	if a.profiles == nil {
		a.profiles = make(map[string]AssistantProviderProfile)
	}
	a.profiles[a.provider] = AssistantProviderProfile{Endpoint: a.baseURL, Model: a.model}
	a.provider = normalizedProvider
	a.baseURL = normalized
	a.model = strings.TrimSpace(model)
	a.profiles[normalizedProvider] = AssistantProviderProfile{Endpoint: normalized, Model: a.model}
	a.configError = ""
	if err := a.persistConfig(); err != nil {
		a.configError = err.Error()
		a.mu.Unlock()
		return AssistantState{}, err
	}
	a.mu.Unlock()

	if key := strings.TrimSpace(apiKey); key != "" {
		store, err := secretstore.Open()
		if err != nil {
			return AssistantState{}, fmt.Errorf("open desktop keyring: %w", err)
		}
		err = store.Set(assistantSecretAttributes(normalizedProvider, normalized), "CyShell Agent API key", key)
		store.Close()
		if err != nil {
			return AssistantState{}, fmt.Errorf("store Assistant API key: %w", err)
		}
		a.keyMu.Lock()
		a.apiKey = key
		a.apiKeyLoaded = true
		a.hasAPIKey = true
		a.keySource = "keyring"
		a.keyMu.Unlock()
	} else if clearKey {
		store, err := secretstore.Open()
		if err != nil {
			return AssistantState{}, fmt.Errorf("open desktop keyring: %w", err)
		}
		err = store.Delete(assistantSecretAttributes(normalizedProvider, normalized))
		if err == nil && normalizedProvider == "openai-compatible" {
			_ = store.Delete(legacyAssistantSecretAttributes(normalized))
		}
		store.Close()
		if err != nil {
			return AssistantState{}, fmt.Errorf("delete Assistant API key: %w", err)
		}
		a.keyMu.Lock()
		a.apiKey = ""
		a.apiKeyLoaded = true
		a.hasAPIKey = false
		a.keySource = ""
		a.keyMu.Unlock()
	} else {
		a.keyMu.Lock()
		a.apiKey = ""
		a.apiKeyLoaded = false
		a.keyMu.Unlock()
		a.refreshKeyPresence(normalizedProvider, normalized)
	}

	_ = ctx
	return a.State(), nil
}

func (a *Assistant) ListModels(ctx context.Context) ([]string, error) {
	if a == nil {
		return nil, errors.New("CyShell Assistant is unavailable")
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.listModelsLocked(ctx)
}

func readLimitedBody(resp *http.Response) ([]byte, error) {
	if resp == nil || resp.Body == nil {
		return nil, errors.New("empty provider response")
	}
	return ioReadAllLimit(resp.Body, assistantMaxResponse)
}

// Isolated for small tests and to keep all provider response limits identical.
var ioReadAllLimit = func(r interface{ Read([]byte) (int, error) }, limit int64) ([]byte, error) {
	return io.ReadAll(io.LimitReader(r, limit))
}
