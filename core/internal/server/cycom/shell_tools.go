package cycom

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/qsipc"
	"github.com/AvengeMedia/DankMaterialShell/core/internal/utils"
	cycomembed "github.com/Cytech-Team/CyComAgent-MCP/embed"
)

const shellToolSource = "cyshell:native"

func registerShellTools(manager *Manager) error {
	if manager == nil || manager.runtime == nil {
		return errors.New("CyCom runtime is nil")
	}
	runtime := manager.runtime

	tools := []cycomembed.Tool{
		{
			Name:        "shell_get_state",
			Title:       "Get CyShell state",
			Description: "Read CyShell settings and live session state through the shell's native IPC surface. Use this before changing desktop settings or shell UI.",
			InputSchema: objectSchema(nil, nil),
			Annotations: map[string]any{"readOnlyHint": true},
			Source:      shellToolSource,
			Handler: func(context.Context, json.RawMessage) (any, error) {
				settingsRaw, err := callShellIPC("settings", "dump", nil)
				if err != nil {
					return nil, err
				}
				sessionRaw, err := callShellIPC("settings", "dumpSession", nil)
				if err != nil {
					return nil, err
				}
				agentRaw, err := callShellIPC("agent", "state", nil)
				if err != nil {
					return nil, err
				}
				return map[string]any{
					"shell":    "CyShell Desktop",
					"settings": decodeJSONOrString(settingsRaw),
					"session":  decodeJSONOrString(sessionRaw),
					"desktop":  decodeJSONOrString(agentRaw),
				}, nil
			},
		},
		{
			Name:        "shell_settings_get",
			Title:       "Read CyShell setting",
			Description: "Read one CyShell setting by its exact key using the shell's native SettingsData API.",
			InputSchema: objectSchema(map[string]any{
				"key": stringSchema("exact CyShell setting key"),
			}, []string{"key"}),
			Annotations: map[string]any{"readOnlyHint": true},
			Source:      shellToolSource,
			Handler: func(_ context.Context, raw json.RawMessage) (any, error) {
				var args struct {
					Key string `json:"key"`
				}
				if err := json.Unmarshal(raw, &args); err != nil {
					return nil, err
				}
				if strings.TrimSpace(args.Key) == "" {
					return nil, errors.New("key is required")
				}
				value, err := callShellIPC("settings", "get", []string{args.Key})
				if err != nil {
					return nil, err
				}
				return map[string]any{"key": args.Key, "value": decodeJSONOrString(value)}, nil
			},
		},
		{
			Name:        "shell_settings_search",
			Title:       "Search CyShell settings",
			Description: "Search CyShell Settings semantically using the same translated index, capability conditions, and ranking as the native Settings UI. Results identify exact scalar setting keys when a row maps directly to SettingsData; use this before shell_settings_set when the key is not already known.",
			InputSchema: objectSchema(map[string]any{
				"query":       stringSchema("natural-language setting name, label, category, description, or keyword"),
				"max_results": integerSchema("maximum results to return; defaults to 15 and is capped at 50"),
			}, []string{"query"}),
			Annotations: map[string]any{"readOnlyHint": true},
			Source:      shellToolSource,
			Handler: func(_ context.Context, raw json.RawMessage) (any, error) {
				var args struct {
					Query      string `json:"query"`
					MaxResults int    `json:"max_results"`
				}
				if err := json.Unmarshal(raw, &args); err != nil {
					return nil, err
				}
				args.Query = strings.TrimSpace(args.Query)
				if args.Query == "" {
					return nil, errors.New("query is required")
				}
				if args.MaxResults <= 0 {
					args.MaxResults = 15
				}
				if args.MaxResults > 50 {
					args.MaxResults = 50
				}
				result, err := callShellIPC("settings", "search", []string{args.Query, fmt.Sprintf("%d", args.MaxResults)})
				if err != nil {
					return nil, err
				}
				return decodeJSONOrString(result), nil
			},
		},
		{
			Name:        "shell_settings_set",
			Title:       "Change CyShell setting",
			Description: "Change one scalar CyShell setting through the shell's validated native SettingsData API. Object and array settings are intentionally not exposed by this tool.",
			InputSchema: objectSchema(map[string]any{
				"key":   stringSchema("exact CyShell setting key"),
				"value": stringSchema("new scalar value encoded as text; booleans use true/false"),
			}, []string{"key", "value"}),
			Source: shellToolSource,
			Handler: func(_ context.Context, raw json.RawMessage) (any, error) {
				var args struct {
					Key   string `json:"key"`
					Value string `json:"value"`
				}
				if err := json.Unmarshal(raw, &args); err != nil {
					return nil, err
				}
				if strings.TrimSpace(args.Key) == "" {
					return nil, errors.New("key is required")
				}
				previousValue := ""
				canUndo := false
				if previousRaw, previousErr := callShellIPC("settings", "get", []string{args.Key}); previousErr == nil {
					previousValue, canUndo = scalarSettingValueString(decodeJSONOrString(previousRaw))
				}

				result, err := callShellIPC("settings", "set", []string{args.Key, args.Value})
				if err != nil {
					return nil, err
				}
				if result != "SETTINGS_SET_SUCCESS" {
					return nil, fmt.Errorf("CyShell rejected setting change: %s", result)
				}
				response := map[string]any{"success": true, "key": args.Key, "result": result}
				if canUndo {
					receipt := manager.issueSettingReceipt(args.Key, args.Value, previousValue)
					response["receipt"] = receipt
				}
				return response, nil
			},
		},
		{
			Name:        "shell_open_settings",
			Title:       "Open CyShell Settings",
			Description: "Open CyShell Settings, optionally at a specific settings page.",
			InputSchema: objectSchema(map[string]any{
				"page":    stringSchema("optional settings page id, typically returned by shell_settings_search"),
				"section": stringSchema("optional Settings search section id to scroll/highlight after opening the page"),
			}, nil),
			Source: shellToolSource,
			Handler: func(_ context.Context, raw json.RawMessage) (any, error) {
				var args struct {
					Page    string `json:"page"`
					Section string `json:"section"`
				}
				if len(raw) > 0 {
					_ = json.Unmarshal(raw, &args)
				}
				var result string
				var err error
				args.Page = strings.TrimSpace(args.Page)
				args.Section = strings.TrimSpace(args.Section)
				if args.Page == "" {
					if args.Section != "" {
						return nil, errors.New("page is required when section is provided")
					}
					result, err = callShellIPC("settings", "open", nil)
				} else if args.Section != "" {
					result, err = callShellIPC("settings", "openSearchResult", []string{args.Page, args.Section})
				} else {
					result, err = callShellIPC("settings", "openWith", []string{args.Page})
				}
				if err != nil {
					return nil, err
				}
				if strings.Contains(result, "FAILED") {
					return nil, errors.New(result)
				}
				return map[string]any{"success": true, "result": result}, nil
			},
		},
		{
			Name:        "shell_launcher",
			Title:       "Control CyShell launcher",
			Description: "Open, close, toggle, or search the native CyShell launcher.",
			InputSchema: objectSchema(map[string]any{
				"action": enumSchema("launcher action", "open", "close", "toggle", "search"),
				"query":  stringSchema("search text when action=search"),
			}, []string{"action"}),
			Source: shellToolSource,
			Handler: func(_ context.Context, raw json.RawMessage) (any, error) {
				var args struct {
					Action string `json:"action"`
					Query  string `json:"query"`
				}
				if err := json.Unmarshal(raw, &args); err != nil {
					return nil, err
				}
				var function string
				var callArgs []string
				switch args.Action {
				case "open", "close", "toggle":
					function = args.Action
				case "search":
					if strings.TrimSpace(args.Query) == "" {
						return nil, errors.New("query is required for search")
					}
					function = "openQuery"
					callArgs = []string{args.Query}
				default:
					return nil, fmt.Errorf("unsupported launcher action %q", args.Action)
				}
				result, err := callShellIPC("launcher", function, callArgs)
				if err != nil {
					return nil, err
				}
				if strings.Contains(result, "FAILED") {
					return nil, errors.New(result)
				}
				return map[string]any{"success": true, "result": result}, nil
			},
		},
		{
			Name:        "application_search",
			Title:       "Search installed applications",
			Description: "Search visible desktop applications with CyShell's native launcher ranking and return stable desktop-entry ids. Use this before application_launch instead of guessing executable names or shell commands.",
			InputSchema: objectSchema(map[string]any{
				"query":       stringSchema("application name, generic name, desktop id, keyword, or description"),
				"max_results": integerSchema("maximum results; defaults to 10 and is capped at 25"),
			}, []string{"query"}),
			Annotations: map[string]any{"readOnlyHint": true},
			Source:      shellToolSource,
			Handler: func(_ context.Context, raw json.RawMessage) (any, error) {
				var args struct {
					Query      string `json:"query"`
					MaxResults int    `json:"max_results"`
				}
				if err := json.Unmarshal(raw, &args); err != nil {
					return nil, err
				}
				args.Query = strings.TrimSpace(args.Query)
				if args.Query == "" {
					return nil, errors.New("query is required")
				}
				if args.MaxResults <= 0 {
					args.MaxResults = 10
				}
				if args.MaxResults > 25 {
					args.MaxResults = 25
				}
				result, err := callShellIPC("launcher", "searchApps", []string{args.Query, strconv.Itoa(args.MaxResults)})
				if err != nil {
					return nil, err
				}
				return decodeJSONOrString(result), nil
			},
		},
		{
			Name:        "application_launch",
			Title:       "Launch an installed application",
			Description: "Launch one installed desktop application by the exact desktop-entry id returned by application_search. This does not execute arbitrary commands.",
			InputSchema: objectSchema(map[string]any{
				"desktop_id": stringSchema("exact desktop-entry id returned by application_search"),
			}, []string{"desktop_id"}),
			Source: shellToolSource,
			Handler: func(_ context.Context, raw json.RawMessage) (any, error) {
				var args struct {
					DesktopID string `json:"desktop_id"`
				}
				if err := json.Unmarshal(raw, &args); err != nil {
					return nil, err
				}
				args.DesktopID = strings.TrimSpace(args.DesktopID)
				if args.DesktopID == "" {
					return nil, errors.New("desktop_id is required")
				}
				result, err := callShellIPC("launcher", "launchApp", []string{args.DesktopID})
				if err != nil {
					return nil, err
				}
				if !strings.HasPrefix(result, "AGENT_APP_LAUNCH_SUCCESS:") {
					return nil, errors.New(result)
				}
				return map[string]any{"success": true, "desktopId": args.DesktopID, "result": result}, nil
			},
		},
		{
			Name:        "shell_control_center",
			Title:       "Control CyShell Control Center",
			Description: "Open, close, or toggle the native CyShell Control Center. An optional section can be supplied when opening.",
			InputSchema: objectSchema(map[string]any{
				"action":  enumSchema("control-center action", "open", "close", "toggle"),
				"section": stringSchema("optional section when opening"),
			}, []string{"action"}),
			Source: shellToolSource,
			Handler: func(_ context.Context, raw json.RawMessage) (any, error) {
				var args struct {
					Action  string `json:"action"`
					Section string `json:"section"`
				}
				if err := json.Unmarshal(raw, &args); err != nil {
					return nil, err
				}
				function := args.Action
				var callArgs []string
				if args.Action == "open" && strings.TrimSpace(args.Section) != "" {
					function = "openWith"
					callArgs = []string{args.Section}
				}
				switch args.Action {
				case "open", "close", "toggle":
				default:
					return nil, fmt.Errorf("unsupported control-center action %q", args.Action)
				}
				result, err := callShellIPC("controlcenter", function, callArgs)
				if err != nil {
					return nil, err
				}
				if strings.Contains(result, "FAILED") {
					return nil, errors.New(result)
				}
				return map[string]any{"success": true, "result": result}, nil
			},
		},

		{
			Name:        "shell_query_ui",
			Title:       "Query CyShell semantic UI",
			Description: "Search CyShell semantic UI nodes, settings pages, surfaces, windows, bars, docks, and workspaces without using screenshots or OCR.",
			InputSchema: objectSchema(map[string]any{
				"query":     stringSchema("text matched against semantic id, role, name, page, app id, title and actions; empty returns a bounded semantic tree"),
				"max_nodes": integerSchema("maximum semantic nodes to return; defaults to 60 and is capped at 200"),
			}, nil),
			Annotations: map[string]any{"readOnlyHint": true},
			Source:      shellToolSource,
			Handler: func(_ context.Context, raw json.RawMessage) (any, error) {
				var args struct {
					Query    string `json:"query"`
					MaxNodes int    `json:"max_nodes"`
				}
				if len(raw) > 0 {
					_ = json.Unmarshal(raw, &args)
				}
				result, err := callShellIPC("agent", "queryUi", []string{args.Query})
				if err != nil {
					return nil, err
				}
				return rankSemanticNodes(decodeJSONOrString(result), args.Query, args.MaxNodes), nil
			},
		},
		{
			Name:        "window_list",
			Title:       "List desktop windows",
			Description: "List live Wayland toplevels known to CyShell with app id, title, pid, state, and screens. Prefer this before targeted window actions.",
			InputSchema: objectSchema(nil, nil),
			Annotations: map[string]any{"readOnlyHint": true},
			Source:      shellToolSource,
			Handler: func(_ context.Context, _ json.RawMessage) (any, error) {
				result, err := callShellIPC("agent", "windows", nil)
				if err != nil {
					return nil, err
				}
				return decodeJSONOrString(result), nil
			},
		},
		{
			Name:        "window_control",
			Title:       "Control a desktop window",
			Description: "Focus, close, minimize, restore, maximize, unmaximize, fullscreen, or unfullscreen exactly one semantic Wayland window selected by index, pid, appId, title, or titleContains.",
			InputSchema: objectSchema(map[string]any{
				"action": enumSchema("window action", "focus", "close", "minimize", "restore", "maximize", "unmaximize", "fullscreen", "unfullscreen"),
				"selector": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"index":         map[string]any{"type": "integer"},
						"pid":           map[string]any{"type": "integer"},
						"appId":         map[string]any{"type": "string"},
						"title":         map[string]any{"type": "string"},
						"titleContains": map[string]any{"type": "string"},
					},
					"additionalProperties": false,
				},
			}, []string{"action", "selector"}),
			Source: shellToolSource,
			Handler: func(_ context.Context, raw json.RawMessage) (any, error) {
				var args struct {
					Action   string         `json:"action"`
					Selector map[string]any `json:"selector"`
				}
				if err := json.Unmarshal(raw, &args); err != nil {
					return nil, err
				}
				if len(args.Selector) == 0 {
					return nil, errors.New("selector is required")
				}
				selector, err := json.Marshal(args.Selector)
				if err != nil {
					return nil, err
				}
				result, err := callShellIPC("agent", "windowAction", []string{args.Action, string(selector)})
				if err != nil {
					return nil, err
				}
				if result != "AGENT_WINDOW_ACTION_SUCCESS" {
					return nil, errors.New(result)
				}
				return map[string]any{"success": true, "action": args.Action, "selector": args.Selector}, nil
			},
		},
		{
			Name:        "workspace_list",
			Title:       "List desktop workspaces",
			Description: "Read semantic workspace state. On Labwc this uses ext-workspace-v1 directly through the CyShell core rather than key injection or screenshots.",
			InputSchema: objectSchema(nil, nil),
			Annotations: map[string]any{"readOnlyHint": true},
			Source:      shellToolSource,
			Handler: func(_ context.Context, _ json.RawMessage) (any, error) {
				result, err := callShellIPC("agent", "workspaces", nil)
				if err != nil {
					return nil, err
				}
				return decodeJSONOrString(result), nil
			},
		},
		{
			Name:        "workspace_focus",
			Title:       "Activate a desktop workspace",
			Description: "Activate exactly one semantic workspace selected by objectId, id, idx, or name. Labwc uses ext-workspace-v1 activation.",
			InputSchema: objectSchema(map[string]any{
				"selector": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"objectId": map[string]any{"type": "integer"},
						"id":       map[string]any{},
						"idx":      map[string]any{"type": "integer"},
						"name":     map[string]any{"type": "string"},
						"output":   map[string]any{"type": "string"},
					},
					"additionalProperties": false,
				},
			}, []string{"selector"}),
			Source: shellToolSource,
			Handler: func(_ context.Context, raw json.RawMessage) (any, error) {
				var args struct {
					Selector map[string]any `json:"selector"`
				}
				if err := json.Unmarshal(raw, &args); err != nil {
					return nil, err
				}
				if len(args.Selector) == 0 {
					return nil, errors.New("selector is required")
				}
				selector, err := json.Marshal(args.Selector)
				if err != nil {
					return nil, err
				}
				result, err := callShellIPC("agent", "workspaceFocus", []string{string(selector)})
				if err != nil {
					return nil, err
				}
				if result != "AGENT_WORKSPACE_ACTIVATE_REQUESTED" {
					return nil, errors.New(result)
				}
				return map[string]any{"success": true, "selector": args.Selector, "result": result}, nil
			},
		},
	}

	for _, tool := range tools {
		if err := runtime.RegisterTool(tool); err != nil {
			return fmt.Errorf("register %s: %w", tool.Name, err)
		}
	}
	return nil
}

func scalarSettingValueString(value any) (string, bool) {
	switch current := value.(type) {
	case bool:
		if current {
			return "true", true
		}
		return "false", true
	case string:
		return current, true
	case float64:
		return strconv.FormatFloat(current, 'f', -1, 64), true
	case float32:
		return strconv.FormatFloat(float64(current), 'f', -1, 64), true
	case int:
		return strconv.Itoa(current), true
	case int64:
		return strconv.FormatInt(current, 10), true
	case json.Number:
		return string(current), true
	default:
		return "", false
	}
}

func callShellIPC(target, function string, args []string) (string, error) {
	sockets := shellSocketCandidates()
	if len(sockets) == 0 {
		return "", errors.New("CyShell UI IPC socket not found; is the shell UI running?")
	}
	var failures []string
	for _, socketPath := range sockets {
		result, isVoid, err := qsipc.Call(socketPath, target, function, args)
		if err == nil {
			if isVoid {
				return "", nil
			}
			return result, nil
		}
		failures = append(failures, filepath.Base(filepath.Dir(socketPath))+": "+err.Error())
	}
	return "", fmt.Errorf("CyShell UI IPC unavailable for %s.%s: %s", target, function, strings.Join(failures, "; "))
}

func shellSocketCandidates() []string {
	if explicit := strings.TrimSpace(os.Getenv("CYSHELL_QS_SOCKET")); explicit != "" {
		return []string{explicit}
	}
	pattern := filepath.Join(utils.RuntimeDir(), "quickshell", "by-pid", "*", "ipc.sock")
	matches, _ := filepath.Glob(pattern)
	sort.SliceStable(matches, func(i, j int) bool {
		ai, errI := os.Stat(matches[i])
		aj, errJ := os.Stat(matches[j])
		if errI != nil {
			return false
		}
		if errJ != nil {
			return true
		}
		return ai.ModTime().After(aj.ModTime())
	})
	return matches
}

func decodeJSONOrString(raw string) any {
	var value any
	if json.Unmarshal([]byte(raw), &value) == nil {
		return value
	}
	return raw
}

func objectSchema(properties map[string]any, required []string) map[string]any {
	if properties == nil {
		properties = map[string]any{}
	}
	schema := map[string]any{
		"type":                 "object",
		"properties":           properties,
		"additionalProperties": false,
	}
	if len(required) > 0 {
		schema["required"] = required
	}
	return schema
}

func stringSchema(description string) map[string]any {
	return map[string]any{"type": "string", "description": description}
}

func enumSchema(description string, values ...string) map[string]any {
	items := make([]any, len(values))
	for i, value := range values {
		items[i] = value
	}
	return map[string]any{"type": "string", "description": description, "enum": items}
}

func rankSemanticNodes(value any, query string, maxNodes int) []any {
	items, ok := value.([]any)
	if !ok {
		return []any{}
	}
	if maxNodes <= 0 {
		maxNodes = 60
	}
	if maxNodes > 200 {
		maxNodes = 200
	}
	query = strings.ToLower(strings.Join(strings.Fields(query), " "))
	type scoredNode struct {
		value any
		score int
		index int
	}
	scored := make([]scoredNode, 0, len(items))
	for index, item := range items {
		score := semanticNodeScore(item, query)
		if query != "" && score <= 0 {
			continue
		}
		scored = append(scored, scoredNode{value: item, score: score, index: index})
	}
	if query != "" {
		sort.SliceStable(scored, func(i, j int) bool {
			if scored[i].score == scored[j].score {
				return scored[i].index < scored[j].index
			}
			return scored[i].score > scored[j].score
		})
	}
	if len(scored) > maxNodes {
		scored = scored[:maxNodes]
	}
	out := make([]any, 0, len(scored))
	for _, item := range scored {
		out = append(out, item.value)
	}
	return out
}

func semanticNodeScore(value any, query string) int {
	if query == "" {
		return 1
	}
	node, ok := value.(map[string]any)
	if !ok {
		data, _ := json.Marshal(value)
		if strings.Contains(strings.ToLower(string(data)), query) {
			return 10
		}
		return 0
	}
	terms := strings.Fields(query)
	score := 0
	matchedTerms := map[string]bool{}
	for _, field := range []string{"id", "name", "title", "appId", "page", "role"} {
		text := strings.ToLower(strings.TrimSpace(fmt.Sprint(node[field])))
		if text == "" || text == "<nil>" {
			continue
		}
		weight := 35
		if field == "id" || field == "name" || field == "title" {
			weight = 50
		}
		if text == query {
			score += weight + 180
		} else if strings.HasPrefix(text, query) {
			score += weight + 35
		} else if strings.Contains(text, query) {
			score += weight
		}
		for _, term := range terms {
			if strings.Contains(text, term) {
				matchedTerms[term] = true
				score += 6
			}
		}
	}
	if actions, ok := node["actions"]; ok {
		data, _ := json.Marshal(actions)
		text := strings.ToLower(string(data))
		if strings.Contains(text, query) {
			score += 25
		}
		for _, term := range terms {
			if strings.Contains(text, term) {
				matchedTerms[term] = true
				score += 3
			}
		}
	}
	if len(terms) > 0 && len(matchedTerms) == len(terms) {
		score += 20
	}
	if score == 0 {
		data, _ := json.Marshal(node)
		text := strings.ToLower(string(data))
		if strings.Contains(text, query) {
			return 10
		}
		all := true
		for _, term := range terms {
			if !strings.Contains(text, term) {
				all = false
				break
			}
		}
		if all && len(terms) > 0 {
			return 5
		}
	}
	return score
}
