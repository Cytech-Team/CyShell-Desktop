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
	"strings"
)

type anthropicTool struct {
	Name        string         `json:"name"`
	Description string         `json:"description,omitempty"`
	InputSchema map[string]any `json:"input_schema"`
}

type anthropicRequest struct {
	Model       string           `json:"model"`
	MaxTokens   int              `json:"max_tokens"`
	System      string           `json:"system,omitempty"`
	Messages    []map[string]any `json:"messages"`
	Tools       []anthropicTool  `json:"tools,omitempty"`
	ToolChoice  map[string]any   `json:"tool_choice,omitempty"`
	Temperature float64          `json:"temperature,omitempty"`
}

type anthropicResponse struct {
	Content []map[string]any `json:"content"`
	Error   *struct {
		Message string `json:"message"`
		Type    string `json:"type,omitempty"`
	} `json:"error,omitempty"`
}

type geminiRequest struct {
	SystemInstruction map[string]any   `json:"systemInstruction,omitempty"`
	Contents          []map[string]any `json:"contents"`
	Tools             []map[string]any `json:"tools,omitempty"`
	GenerationConfig  map[string]any   `json:"generationConfig,omitempty"`
}

type geminiResponse struct {
	Candidates []struct {
		Content struct {
			Role  string           `json:"role"`
			Parts []map[string]any `json:"parts"`
		} `json:"content"`
	} `json:"candidates"`
	Error *struct {
		Message string `json:"message"`
		Status  string `json:"status,omitempty"`
	} `json:"error,omitempty"`
}

func (a *Assistant) completeAnthropic(ctx context.Context, model string, messages []assistantMessage, tools []assistantToolDefinition) (assistantMessage, error) {
	system, converted := anthropicMessages(messages)
	definitions := make([]anthropicTool, 0, len(tools))
	for _, tool := range tools {
		definitions = append(definitions, anthropicTool{
			Name:        tool.Function.Name,
			Description: tool.Function.Description,
			InputSchema: tool.Function.Parameters,
		})
	}
	body := anthropicRequest{
		Model:       model,
		MaxTokens:   4096,
		System:      system,
		Messages:    converted,
		Tools:       definitions,
		ToolChoice:  map[string]any{"type": "auto"},
		Temperature: 0.2,
	}
	data, err := json.Marshal(body)
	if err != nil {
		return assistantMessage{}, err
	}
	endpoint, err := anthropicMessagesURL(a.baseURL)
	if err != nil {
		return assistantMessage{}, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(data))
	if err != nil {
		return assistantMessage{}, err
	}
	key, err := a.providerAPIKey("anthropic", a.baseURL)
	if err != nil {
		return assistantMessage{}, err
	}
	if key == "" {
		return assistantMessage{}, errors.New("Anthropic provider requires an API key")
	}
	req.Header.Set("x-api-key", key)
	req.Header.Set("anthropic-version", "2023-06-01")
	req.Header.Set("content-type", "application/json")
	req.Header.Set("user-agent", "CyShell-Desktop/agent")
	resp, err := a.client.Do(req)
	if err != nil {
		return assistantMessage{}, fmt.Errorf("Anthropic request failed: %w", err)
	}
	defer resp.Body.Close()
	responseData, err := io.ReadAll(io.LimitReader(resp.Body, assistantMaxResponse))
	if err != nil {
		return assistantMessage{}, err
	}
	var parsed anthropicResponse
	if err := json.Unmarshal(responseData, &parsed); err != nil {
		return assistantMessage{}, fmt.Errorf("decode Anthropic response: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		message := strings.TrimSpace(string(responseData))
		if parsed.Error != nil && parsed.Error.Message != "" {
			message = parsed.Error.Message
		}
		return assistantMessage{}, fmt.Errorf("Anthropic returned HTTP %d: %s", resp.StatusCode, message)
	}
	if parsed.Error != nil {
		return assistantMessage{}, errors.New(parsed.Error.Message)
	}
	return anthropicResponseMessage(parsed.Content)
}

func anthropicMessages(messages []assistantMessage) (string, []map[string]any) {
	system := ""
	out := make([]map[string]any, 0, len(messages))
	for _, message := range messages {
		switch message.Role {
		case "system":
			if message.Content != "" {
				if system != "" {
					system += "\n\n"
				}
				system += message.Content
			}
		case "user":
			appendAnthropicContent(&out, "user", []any{map[string]any{"type": "text", "text": message.Content}})
		case "assistant":
			blocks := make([]any, 0, len(message.ToolCalls)+1)
			if strings.TrimSpace(message.Content) != "" {
				blocks = append(blocks, map[string]any{"type": "text", "text": message.Content})
			}
			for _, call := range message.ToolCalls {
				var input any = map[string]any{}
				if strings.TrimSpace(call.Function.Arguments) != "" {
					_ = json.Unmarshal([]byte(call.Function.Arguments), &input)
				}
				blocks = append(blocks, map[string]any{
					"type":  "tool_use",
					"id":    call.ID,
					"name":  call.Function.Name,
					"input": input,
				})
			}
			appendAnthropicContent(&out, "assistant", blocks)
		case "tool":
			block := map[string]any{
				"type":        "tool_result",
				"tool_use_id": message.ToolCallID,
				"content":     message.Content,
			}
			if strings.Contains(message.Content, `"error"`) {
				block["is_error"] = true
			}
			appendAnthropicContent(&out, "user", []any{block})
		}
	}
	return system, out
}

func appendAnthropicContent(messages *[]map[string]any, role string, blocks []any) {
	if len(blocks) == 0 {
		return
	}
	if len(*messages) > 0 {
		last := (*messages)[len(*messages)-1]
		if last["role"] == role {
			if existing, ok := last["content"].([]any); ok {
				last["content"] = append(existing, blocks...)
				(*messages)[len(*messages)-1] = last
				return
			}
		}
	}
	*messages = append(*messages, map[string]any{"role": role, "content": blocks})
}

func anthropicResponseMessage(blocks []map[string]any) (assistantMessage, error) {
	message := assistantMessage{Role: "assistant"}
	texts := []string{}
	for _, block := range blocks {
		typeName, _ := block["type"].(string)
		switch typeName {
		case "text":
			if text, _ := block["text"].(string); strings.TrimSpace(text) != "" {
				texts = append(texts, text)
			}
		case "tool_use":
			id, _ := block["id"].(string)
			name, _ := block["name"].(string)
			if id == "" || name == "" {
				continue
			}
			input := block["input"]
			arguments, _ := json.Marshal(input)
			call := assistantToolCall{ID: id, Type: "function"}
			call.Function.Name = name
			call.Function.Arguments = string(arguments)
			message.ToolCalls = append(message.ToolCalls, call)
		}
	}
	message.Content = strings.Join(texts, "\n")
	if message.Content == "" && len(message.ToolCalls) == 0 {
		return assistantMessage{}, errors.New("Anthropic returned no text or tool calls")
	}
	return message, nil
}

func (a *Assistant) completeGemini(ctx context.Context, model string, messages []assistantMessage, tools []assistantToolDefinition) (assistantMessage, error) {
	system, contents := geminiContents(messages)
	declarations := make([]any, 0, len(tools))
	for _, tool := range tools {
		declarations = append(declarations, map[string]any{
			"name":        tool.Function.Name,
			"description": tool.Function.Description,
			"parameters":  tool.Function.Parameters,
		})
	}
	body := geminiRequest{
		Contents: contents,
		Tools: []map[string]any{{
			"functionDeclarations": declarations,
		}},
		GenerationConfig: map[string]any{"temperature": 0.2},
	}
	if system != "" {
		body.SystemInstruction = map[string]any{"parts": []any{map[string]any{"text": system}}}
	}
	data, err := json.Marshal(body)
	if err != nil {
		return assistantMessage{}, err
	}
	endpoint, err := geminiGenerateURL(a.baseURL, model)
	if err != nil {
		return assistantMessage{}, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(data))
	if err != nil {
		return assistantMessage{}, err
	}
	key, err := a.providerAPIKey("gemini", a.baseURL)
	if err != nil {
		return assistantMessage{}, err
	}
	if key == "" {
		return assistantMessage{}, errors.New("Gemini provider requires an API key")
	}
	req.Header.Set("x-goog-api-key", key)
	req.Header.Set("content-type", "application/json")
	req.Header.Set("user-agent", "CyShell-Desktop/agent")
	resp, err := a.client.Do(req)
	if err != nil {
		return assistantMessage{}, fmt.Errorf("Gemini request failed: %w", err)
	}
	defer resp.Body.Close()
	responseData, err := io.ReadAll(io.LimitReader(resp.Body, assistantMaxResponse))
	if err != nil {
		return assistantMessage{}, err
	}
	var parsed geminiResponse
	if err := json.Unmarshal(responseData, &parsed); err != nil {
		return assistantMessage{}, fmt.Errorf("decode Gemini response: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		message := strings.TrimSpace(string(responseData))
		if parsed.Error != nil && parsed.Error.Message != "" {
			message = parsed.Error.Message
		}
		return assistantMessage{}, fmt.Errorf("Gemini returned HTTP %d: %s", resp.StatusCode, message)
	}
	if parsed.Error != nil {
		return assistantMessage{}, errors.New(parsed.Error.Message)
	}
	if len(parsed.Candidates) == 0 {
		return assistantMessage{}, errors.New("Gemini returned no candidates")
	}
	return geminiResponseMessage(parsed.Candidates[0].Content.Parts)
}

func geminiContents(messages []assistantMessage) (string, []map[string]any) {
	system := ""
	out := make([]map[string]any, 0, len(messages))
	for _, message := range messages {
		switch message.Role {
		case "system":
			if message.Content != "" {
				if system != "" {
					system += "\n\n"
				}
				system += message.Content
			}
		case "user":
			appendGeminiContent(&out, "user", []any{map[string]any{"text": message.Content}})
		case "assistant":
			parts := make([]any, 0, len(message.ToolCalls)+1)
			if len(message.ProviderParts) > 0 {
				for _, part := range message.ProviderParts {
					parts = append(parts, cloneMap(part))
				}
			} else {
				if strings.TrimSpace(message.Content) != "" {
					parts = append(parts, map[string]any{"text": message.Content})
				}
				for _, call := range message.ToolCalls {
					var args any = map[string]any{}
					if strings.TrimSpace(call.Function.Arguments) != "" {
						_ = json.Unmarshal([]byte(call.Function.Arguments), &args)
					}
					fc := map[string]any{"name": call.Function.Name, "args": args}
					if call.ID != "" {
						fc["id"] = call.ID
					}
					parts = append(parts, map[string]any{"functionCall": fc})
				}
			}
			appendGeminiContent(&out, "model", parts)
		case "tool":
			response := any(map[string]any{"output": message.Content})
			var decoded any
			if json.Unmarshal([]byte(message.Content), &decoded) == nil {
				if object, ok := decoded.(map[string]any); ok {
					response = object
				} else {
					response = map[string]any{"output": decoded}
				}
			}
			fr := map[string]any{
				"name":     message.Name,
				"response": response,
			}
			if len(message.ProviderParts) > 0 {
				if originalFC, ok := message.ProviderParts[0]["functionCall"].(map[string]any); ok {
					if id, ok := originalFC["id"].(string); ok && id != "" {
						fr["id"] = id
					}
				}
			}
			appendGeminiContent(&out, "user", []any{map[string]any{"functionResponse": fr}})
		}
	}
	return system, out
}

func appendGeminiContent(contents *[]map[string]any, role string, parts []any) {
	if len(parts) == 0 {
		return
	}
	if len(*contents) > 0 {
		last := (*contents)[len(*contents)-1]
		if last["role"] == role {
			if existing, ok := last["parts"].([]any); ok {
				last["parts"] = append(existing, parts...)
				(*contents)[len(*contents)-1] = last
				return
			}
		}
	}
	*contents = append(*contents, map[string]any{"role": role, "parts": parts})
}

func cloneMap(source map[string]any) map[string]any {
	if source == nil {
		return nil
	}
	data, err := json.Marshal(source)
	if err != nil {
		return source
	}
	var out map[string]any
	if json.Unmarshal(data, &out) != nil {
		return source
	}
	return out
}

func geminiResponseMessage(parts []map[string]any) (assistantMessage, error) {
	message := assistantMessage{Role: "assistant", ProviderParts: make([]map[string]any, 0, len(parts))}
	texts := []string{}
	for index, part := range parts {
		message.ProviderParts = append(message.ProviderParts, cloneMap(part))
		if text, _ := part["text"].(string); strings.TrimSpace(text) != "" {
			texts = append(texts, text)
		}
		fc, ok := part["functionCall"].(map[string]any)
		if !ok {
			continue
		}
		name, _ := fc["name"].(string)
		if name == "" {
			continue
		}
		id, _ := fc["id"].(string)
		if id == "" {
			id = fmt.Sprintf("gemini-call-%d-%s", index, name)
		}
		arguments, _ := json.Marshal(fc["args"])
		call := assistantToolCall{ID: id, Type: "function", ProviderPart: cloneMap(part)}
		call.Function.Name = name
		call.Function.Arguments = string(arguments)
		message.ToolCalls = append(message.ToolCalls, call)
	}
	message.Content = strings.Join(texts, "\n")
	if message.Content == "" && len(message.ToolCalls) == 0 {
		return assistantMessage{}, errors.New("Gemini returned no text or function calls")
	}
	return message, nil
}

func (a *Assistant) listModelsLocked(ctx context.Context) ([]string, error) {
	switch a.provider {
	case "anthropic":
		return a.listAnthropicModels(ctx)
	case "gemini":
		return a.listGeminiModels(ctx)
	default:
		return a.listOpenAIModels(ctx)
	}
}

func (a *Assistant) listOpenAIModels(ctx context.Context) ([]string, error) {
	modelsURL, err := a.modelsURL()
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, modelsURL, nil)
	if err != nil {
		return nil, err
	}
	if err := a.applyHeaders(req); err != nil {
		return nil, err
	}
	resp, err := a.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("connect to Assistant provider %s: %w", a.baseURL, err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, assistantMaxResponse))
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("Assistant provider models request returned HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	var parsed struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("decode Assistant model list: %w", err)
	}
	return modelIDsFromData(parsed.Data), nil
}

func (a *Assistant) listAnthropicModels(ctx context.Context) ([]string, error) {
	endpoint, err := anthropicModelsURL(a.baseURL)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}
	key, err := a.providerAPIKey("anthropic", a.baseURL)
	if err != nil {
		return nil, err
	}
	if key == "" {
		return nil, errors.New("Anthropic provider requires an API key")
	}
	req.Header.Set("x-api-key", key)
	req.Header.Set("anthropic-version", "2023-06-01")
	resp, err := a.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, assistantMaxResponse))
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("Anthropic models returned HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	var parsed struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, err
	}
	return modelIDsFromData(parsed.Data), nil
}

func (a *Assistant) listGeminiModels(ctx context.Context) ([]string, error) {
	endpoint, err := geminiModelsURL(a.baseURL)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}
	key, err := a.providerAPIKey("gemini", a.baseURL)
	if err != nil {
		return nil, err
	}
	if key == "" {
		return nil, errors.New("Gemini provider requires an API key")
	}
	req.Header.Set("x-goog-api-key", key)
	resp, err := a.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, assistantMaxResponse))
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("Gemini models returned HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	var parsed struct {
		Models []struct {
			Name                       string   `json:"name"`
			SupportedGenerationMethods []string `json:"supportedGenerationMethods"`
		} `json:"models"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, err
	}
	models := []string{}
	for _, item := range parsed.Models {
		if len(item.SupportedGenerationMethods) > 0 && !containsString(item.SupportedGenerationMethods, "generateContent") {
			continue
		}
		name := strings.TrimPrefix(strings.TrimSpace(item.Name), "models/")
		if name != "" {
			models = append(models, name)
		}
	}
	return models, nil
}

func modelIDsFromData[T interface {
	~struct {
		ID string `json:"id"`
	}
}](items []T) []string {
	models := make([]string, 0, len(items))
	for _, item := range items {
		data, _ := json.Marshal(item)
		var raw struct {
			ID string `json:"id"`
		}
		_ = json.Unmarshal(data, &raw)
		if id := strings.TrimSpace(raw.ID); id != "" {
			models = append(models, id)
		}
	}
	return models
}

func containsString(values []string, wanted string) bool {
	for _, value := range values {
		if value == wanted {
			return true
		}
	}
	return false
}

func anthropicMessagesURL(baseURL string) (string, error) {
	return providerURL(baseURL, "/v1/messages", "/messages")
}

func anthropicModelsURL(baseURL string) (string, error) {
	return providerURL(baseURL, "/v1/models", "/models")
}

func providerURL(baseURL, rootSuffix, versionSuffix string) (string, error) {
	base, err := url.Parse(baseURL)
	if err != nil || base.Scheme == "" || base.Host == "" {
		return "", fmt.Errorf("invalid Assistant endpoint %q", baseURL)
	}
	if base.Scheme != "http" && base.Scheme != "https" {
		return "", errors.New("Assistant endpoint must use http or https")
	}
	path := strings.TrimRight(base.Path, "/")
	if strings.HasSuffix(path, rootSuffix) {
		base.Path = path
	} else if strings.HasSuffix(path, "/v1") {
		base.Path = path + versionSuffix
	} else {
		base.Path = path + rootSuffix
	}
	base.RawQuery = ""
	base.Fragment = ""
	return base.String(), nil
}

func geminiModelsURL(baseURL string) (string, error) {
	base, err := url.Parse(baseURL)
	if err != nil || base.Scheme == "" || base.Host == "" {
		return "", fmt.Errorf("invalid Assistant endpoint %q", baseURL)
	}
	if base.Scheme != "http" && base.Scheme != "https" {
		return "", errors.New("Assistant endpoint must use http or https")
	}
	path := strings.TrimRight(base.Path, "/")
	if !strings.HasSuffix(path, "/models") {
		path += "/models"
	}
	base.Path = path
	base.RawQuery = ""
	base.Fragment = ""
	return base.String(), nil
}

func geminiGenerateURL(baseURL, model string) (string, error) {
	base, err := url.Parse(baseURL)
	if err != nil || base.Scheme == "" || base.Host == "" {
		return "", fmt.Errorf("invalid Assistant endpoint %q", baseURL)
	}
	if base.Scheme != "http" && base.Scheme != "https" {
		return "", errors.New("Assistant endpoint must use http or https")
	}
	model = strings.TrimPrefix(strings.TrimSpace(model), "models/")
	if model == "" {
		return "", errors.New("Gemini model is required")
	}
	base.Path = strings.TrimRight(base.Path, "/") + "/models/" + url.PathEscape(model) + ":generateContent"
	base.RawQuery = ""
	base.Fragment = ""
	return base.String(), nil
}
