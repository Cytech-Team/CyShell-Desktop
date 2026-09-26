package cycom

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"
)

const (
	assistantMaxTurns       = 20
	assistantMaxToolRounds  = 8
	assistantMaxResponse    = 8 << 20
	assistantMaxToolContent = 128 << 10
)

type AssistantProviderProfile struct {
	Endpoint string `json:"endpoint"`
	Model    string `json:"model,omitempty"`
}

type AssistantState struct {
	Provider   string                              `json:"provider"`
	Endpoint   string                              `json:"endpoint"`
	Model      string                              `json:"model,omitempty"`
	Configured bool                                `json:"configured"`
	HasAPIKey  bool                                `json:"hasApiKey"`
	KeySource  string                              `json:"keySource,omitempty"`
	Profiles   map[string]AssistantProviderProfile `json:"profiles,omitempty"`
	Error      string                              `json:"error,omitempty"`
}

type ChatHistoryMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type ChatResult struct {
	Message   string   `json:"message"`
	Model     string   `json:"model"`
	ToolCalls []string `json:"toolCalls,omitempty"`
}

type assistantMessage struct {
	Role          string              `json:"role"`
	Content       string              `json:"content,omitempty"`
	ToolCalls     []assistantToolCall `json:"tool_calls,omitempty"`
	ToolCallID    string              `json:"tool_call_id,omitempty"`
	Name          string              `json:"name,omitempty"`
	ProviderParts []map[string]any    `json:"-"`
}

type assistantToolCall struct {
	ID       string `json:"id"`
	Type     string `json:"type"`
	Function struct {
		Name      string `json:"name"`
		Arguments string `json:"arguments"`
	} `json:"function"`
	ProviderPart map[string]any `json:"-"`
}

type assistantToolDefinition struct {
	Type     string `json:"type"`
	Function struct {
		Name        string         `json:"name"`
		Description string         `json:"description,omitempty"`
		Parameters  map[string]any `json:"parameters"`
	} `json:"function"`
}

type assistantRequest struct {
	Model       string                    `json:"model"`
	Messages    []assistantMessage        `json:"messages"`
	Tools       []assistantToolDefinition `json:"tools,omitempty"`
	ToolChoice  string                    `json:"tool_choice,omitempty"`
	Temperature float64                   `json:"temperature,omitempty"`
}

type assistantResponse struct {
	Choices []struct {
		Message assistantMessage `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
		Type    string `json:"type,omitempty"`
	} `json:"error,omitempty"`
}

type Assistant struct {
	manager     *Manager
	client      *http.Client
	provider    string
	baseURL     string
	configPath  string
	historyPath string

	mu          sync.Mutex
	model       string
	profiles    map[string]AssistantProviderProfile
	history     []ChatHistoryMessage
	configError string

	keyMu        sync.Mutex
	apiKey       string
	apiKeyLoaded bool
	hasAPIKey    bool
	keySource    string
	envAPIKey    bool
}

func NewAssistant(manager *Manager) *Assistant {
	a := &Assistant{
		manager:     manager,
		client:      &http.Client{Timeout: 120 * time.Second},
		provider:    "openai-compatible",
		baseURL:     defaultAssistantEndpoint("openai-compatible"),
		configPath:  assistantConfigPath(manager),
		historyPath: assistantHistoryPath(manager),
		profiles:    make(map[string]AssistantProviderProfile),
		history:     []ChatHistoryMessage{},
	}
	if err := a.loadConfig(); err != nil {
		a.configError = err.Error()
	}
	envProviderSet := false
	if provider := strings.TrimSpace(os.Getenv("CYSHELL_AGENT_PROVIDER")); provider != "" {
		if normalized, ok := normalizeAssistantProvider(provider); ok {
			a.provider = normalized
			envProviderSet = true
		} else {
			a.configError = "invalid CYSHELL_AGENT_PROVIDER " + provider
		}
	}
	if raw := strings.TrimSpace(os.Getenv("CYSHELL_AGENT_BASE_URL")); raw != "" {
		if endpoint, err := normalizeAssistantEndpoint(raw); err == nil {
			a.baseURL = endpoint
		} else {
			a.configError = err.Error()
		}
	} else if envProviderSet {
		a.baseURL = defaultAssistantEndpoint(a.provider)
	}
	if model := strings.TrimSpace(os.Getenv("CYSHELL_AGENT_MODEL")); model != "" {
		a.model = model
	}
	if key := strings.TrimSpace(os.Getenv("CYSHELL_AGENT_API_KEY")); key != "" {
		a.apiKey = key
		a.apiKeyLoaded = true
		a.hasAPIKey = true
		a.keySource = "environment"
		a.envAPIKey = true
	} else {
		a.refreshKeyPresence(a.provider, a.baseURL)
	}
	if err := a.loadHistory(); err != nil && a.configError == "" {
		a.configError = err.Error()
	}
	return a
}

func (a *Assistant) State() AssistantState {
	if a == nil {
		return AssistantState{Provider: "openai-compatible"}
	}
	a.mu.Lock()
	provider := a.provider
	endpoint := a.baseURL
	model := a.model
	configError := a.configError
	profiles := make(map[string]AssistantProviderProfile, len(a.profiles)+1)
	for id, profile := range a.profiles {
		profiles[id] = profile
	}
	profiles[provider] = AssistantProviderProfile{Endpoint: endpoint, Model: model}
	a.keyMu.Lock()
	hasAPIKey := a.hasAPIKey
	keySource := a.keySource
	a.keyMu.Unlock()
	a.mu.Unlock()
	return AssistantState{
		Provider:   provider,
		Endpoint:   endpoint,
		Model:      model,
		Configured: endpoint != "",
		HasAPIKey:  hasAPIKey,
		KeySource:  keySource,
		Profiles:   profiles,
		Error:      configError,
	}
}

func (a *Assistant) History() []ChatHistoryMessage {
	if a == nil {
		return []ChatHistoryMessage{}
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	return append([]ChatHistoryMessage(nil), a.history...)
}

func (a *Assistant) Clear() {
	if a == nil {
		return
	}
	a.mu.Lock()
	a.history = []ChatHistoryMessage{}
	_ = a.persistHistoryLocked()
	a.mu.Unlock()
}

func (a *Assistant) Chat(ctx context.Context, prompt string) (ChatResult, error) {
	if a == nil || a.manager == nil {
		return ChatResult{}, errors.New("CyShell Assistant is unavailable")
	}
	prompt = strings.TrimSpace(prompt)
	if prompt == "" {
		return ChatResult{}, errors.New("message is required")
	}
	if !a.manager.enabled.Load() {
		return ChatResult{}, errors.New("CyShell Agent is disabled")
	}

	ctx, done := a.manager.trackContext(ctx)
	defer done()

	a.mu.Lock()
	defer a.mu.Unlock()

	model, err := a.resolveModel(ctx)
	if err != nil {
		return ChatResult{}, err
	}

	messages := make([]assistantMessage, 0, len(a.history)+4)
	messages = append(messages, assistantMessage{Role: "system", Content: assistantSystemPrompt(a.manager.controlEnabled.Load())})
	for _, item := range a.history {
		messages = append(messages, assistantMessage{Role: item.Role, Content: item.Content})
	}
	messages = append(messages, assistantMessage{Role: "user", Content: prompt})

	tools := a.toolDefinitions()
	usedTools := []string{}
	for round := 0; round < assistantMaxToolRounds; round++ {
		message, err := a.complete(ctx, model, messages, tools)
		if err != nil {
			return ChatResult{}, err
		}
		if len(message.ToolCalls) == 0 {
			answer := strings.TrimSpace(message.Content)
			if answer == "" {
				return ChatResult{}, errors.New("model returned an empty response")
			}
			a.history = append(a.history,
				ChatHistoryMessage{Role: "user", Content: prompt},
				ChatHistoryMessage{Role: "assistant", Content: answer},
			)
			if len(a.history) > assistantMaxTurns*2 {
				a.history = append([]ChatHistoryMessage(nil), a.history[len(a.history)-assistantMaxTurns*2:]...)
			}
			if err := a.persistHistoryLocked(); err != nil {
				a.configError = err.Error()
			}
			return ChatResult{Message: answer, Model: model, ToolCalls: usedTools}, nil
		}

		messages = append(messages, message)
		for _, call := range message.ToolCalls {
			name := strings.TrimSpace(call.Function.Name)
			if name == "" {
				continue
			}
			usedTools = append(usedTools, name)
			content := a.executeTool(ctx, name, call.Function.Arguments, prompt)
			toolMessage := assistantMessage{
				Role:       "tool",
				ToolCallID: call.ID,
				Name:       name,
				Content:    content,
			}
			if call.ProviderPart != nil {
				toolMessage.ProviderParts = []map[string]any{call.ProviderPart}
			}
			messages = append(messages, toolMessage)
		}
	}
	return ChatResult{}, fmt.Errorf("assistant exceeded %d tool rounds", assistantMaxToolRounds)
}

func assistantSystemPrompt(controlEnabled bool) string {
	control := "Computer control is enabled."
	if !controlEnabled {
		control = "Computer control is disabled. Read-only tools may be used, but do not claim that a blocked state-changing action succeeded."
	}
	return "You are the built-in CyShell Desktop assistant. " + control + " Prefer desktop_get_context and desktop_query for broad desktop tasks, then shell/window/workspace/app semantic tools before screenshots, raw input, shell commands, or file inspection. When a CyShell setting key is not already exact, use shell_settings_search first and only write a result that exposes a writable settingKey; do not guess SettingsData keys. When opening an installed application, use application_search followed by application_launch before process_exec so the desktop entry and launch semantics stay native. Reuse desktop_get_context contextDigest and sectionDigests via known_digest/known_sections on repeated reads to avoid returning unchanged context. Use app_query_ui for third-party application UI before screenshot-based fallback. Every tool call must include a concise reason grounded in the user's request. Respect CyShell permission-scope errors instead of trying to bypass them with a lower-level tool. Verify state-changing actions when a read-back tool is available. Keep reversible action receipts from desktop_action and shell_settings_set available for a user-requested undo; use desktop_undo only when the user asks to roll back or clearly correct the immediately preceding semantic action. Do not expose secrets from the environment or unrelated files."
}

func (a *Assistant) toolDefinitions() []assistantToolDefinition {
	items := a.manager.runtime.ListTools()
	out := make([]assistantToolDefinition, 0, len(items))
	for _, tool := range items {
		if !assistantToolAllowed(tool.Name) {
			continue
		}
		var def assistantToolDefinition
		def.Type = "function"
		def.Function.Name = tool.Name
		def.Function.Description = tool.Description
		def.Function.Parameters = tool.InputSchema
		out = append(out, def)
	}
	return out
}

func assistantToolAllowed(name string) bool {
	for _, prefix := range []string{"desktop_", "app_", "shell_", "window_", "workspace_", "anyapp_", "fs_", "process_", "job_", "target_"} {
		if strings.HasPrefix(name, prefix) {
			return true
		}
	}
	switch name {
	case "system_info", "capabilities_list", "service_control", "network_request", "network_resolve", "network_tcp", "display_outputs", "display_output_control", "policy_get", "audit_tail", "machine_poweroff", "machine_restart", "session_logout":
		return true
	default:
		return false
	}
}

func (a *Assistant) executeTool(ctx context.Context, name, arguments, prompt string) string {
	var args map[string]any
	if err := json.Unmarshal([]byte(arguments), &args); err != nil {
		return marshalAssistantToolResult(map[string]any{"error": "invalid tool arguments: " + err.Error()})
	}
	if args == nil {
		args = map[string]any{}
	}
	if reason, ok := args["reason"].(string); !ok || strings.TrimSpace(reason) == "" {
		args["reason"] = "Built-in CyShell Assistant handling user request: " + trimForReason(prompt)
	}
	raw, err := json.Marshal(args)
	if err != nil {
		return marshalAssistantToolResult(map[string]any{"error": err.Error()})
	}
	value, err := a.manager.CallWithOrigin(ctx, name, raw, CallOrigin{Kind: "assistant", Name: "Built-in Assistant"})
	if err != nil {
		return marshalAssistantToolResult(map[string]any{"error": err.Error()})
	}
	return marshalAssistantToolResult(value)
}

func trimForReason(value string) string {
	value = strings.Join(strings.Fields(value), " ")
	if len(value) > 180 {
		return value[:180] + "..."
	}
	return value
}

func marshalAssistantToolResult(value any) string {
	data, err := json.Marshal(value)
	if err != nil {
		return fmt.Sprintf(`{"error":%q}`, err.Error())
	}
	if len(data) <= assistantMaxToolContent {
		return string(data)
	}
	preview := string(data[:assistantMaxToolContent])
	encoded, _ := json.Marshal(map[string]any{"truncated": true, "preview": preview})
	return string(encoded)
}

func (a *Assistant) resolveModel(ctx context.Context) (string, error) {
	if strings.TrimSpace(a.model) != "" {
		return a.model, nil
	}
	models, err := a.listModelsLocked(ctx)
	if err != nil {
		return "", err
	}
	if len(models) == 0 || strings.TrimSpace(models[0]) == "" {
		return "", errors.New("Assistant provider returned no models; configure a model explicitly")
	}
	a.model = models[0]
	if err := a.persistConfig(); err != nil {
		a.configError = err.Error()
	}
	return a.model, nil
}

func (a *Assistant) complete(ctx context.Context, model string, messages []assistantMessage, tools []assistantToolDefinition) (assistantMessage, error) {
	switch a.provider {
	case "anthropic":
		return a.completeAnthropic(ctx, model, messages, tools)
	case "gemini":
		return a.completeGemini(ctx, model, messages, tools)
	default:
		return a.completeOpenAI(ctx, model, messages, tools)
	}
}

func (a *Assistant) completeOpenAI(ctx context.Context, model string, messages []assistantMessage, tools []assistantToolDefinition) (assistantMessage, error) {
	body := assistantRequest{
		Model:       model,
		Messages:    messages,
		Tools:       tools,
		ToolChoice:  "auto",
		Temperature: 0.2,
	}
	data, err := json.Marshal(body)
	if err != nil {
		return assistantMessage{}, err
	}
	chatURL, err := a.chatURL()
	if err != nil {
		return assistantMessage{}, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, chatURL, bytes.NewReader(data))
	if err != nil {
		return assistantMessage{}, err
	}
	if err := a.applyHeaders(req); err != nil {
		return assistantMessage{}, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := a.client.Do(req)
	if err != nil {
		return assistantMessage{}, fmt.Errorf("Assistant provider request failed: %w", err)
	}
	defer resp.Body.Close()
	responseData, err := io.ReadAll(io.LimitReader(resp.Body, assistantMaxResponse))
	if err != nil {
		return assistantMessage{}, err
	}
	var parsed assistantResponse
	if err := json.Unmarshal(responseData, &parsed); err != nil {
		return assistantMessage{}, fmt.Errorf("decode Assistant response: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		message := strings.TrimSpace(string(responseData))
		if parsed.Error != nil && parsed.Error.Message != "" {
			message = parsed.Error.Message
		}
		return assistantMessage{}, fmt.Errorf("Assistant provider returned HTTP %d: %s", resp.StatusCode, message)
	}
	if parsed.Error != nil {
		return assistantMessage{}, errors.New(parsed.Error.Message)
	}
	if len(parsed.Choices) == 0 {
		return assistantMessage{}, errors.New("Assistant provider returned no choices")
	}
	message := parsed.Choices[0].Message
	if message.Role == "" {
		message.Role = "assistant"
	}
	return message, nil
}

func (a *Assistant) applyHeaders(req *http.Request) error {
	key, err := a.providerAPIKey(a.provider, a.baseURL)
	if err != nil {
		return err
	}
	if key != "" {
		req.Header.Set("Authorization", "Bearer "+key)
	}
	req.Header.Set("User-Agent", "CyShell-Desktop/agent")
	return nil
}

func (a *Assistant) modelsURL() (string, error) {
	base, err := url.Parse(a.baseURL)
	if err != nil || base.Scheme == "" || base.Host == "" {
		return "", fmt.Errorf("invalid Assistant endpoint %q", a.baseURL)
	}
	if base.Scheme != "http" && base.Scheme != "https" {
		return "", errors.New("Assistant provider URL must use http or https")
	}
	if strings.HasSuffix(base.Path, "/chat/completions") {
		base.Path = strings.TrimSuffix(base.Path, "/chat/completions") + "/models"
	} else {
		base.Path = strings.TrimRight(base.Path, "/") + "/models"
	}
	base.RawQuery = ""
	base.Fragment = ""
	return base.String(), nil
}

func (a *Assistant) chatURL() (string, error) {
	base, err := url.Parse(a.baseURL)
	if err != nil || base.Scheme == "" || base.Host == "" {
		return "", fmt.Errorf("invalid Assistant endpoint %q", a.baseURL)
	}
	if base.Scheme != "http" && base.Scheme != "https" {
		return "", errors.New("Assistant provider URL must use http or https")
	}
	if !strings.HasSuffix(base.Path, "/chat/completions") {
		base.Path = strings.TrimRight(base.Path, "/") + "/chat/completions"
	}
	base.RawQuery = ""
	base.Fragment = ""
	return base.String(), nil
}
