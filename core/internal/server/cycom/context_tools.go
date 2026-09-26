package cycom

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"

	cycomembed "github.com/Cytech-Team/CyComAgent-MCP/embed"
)

const contextToolSource = "cyshell:context"

func registerContextTools(manager *Manager) error {
	if manager == nil || manager.runtime == nil {
		return errors.New("CyShell Agent manager is unavailable")
	}

	tools := []cycomembed.Tool{
		{
			Name:        "desktop_get_context",
			Title:       "Get unified desktop context",
			Description: "Return one structured CyShell desktop context graph spanning shell surfaces, windows, workspaces, permissions, and optionally the focused third-party app and system information. Prefer this as the first read for broad desktop tasks.",
			InputSchema: objectSchema(map[string]any{
				"include_app":        boolSchema("include focused third-party application semantic state through Any App / AT-SPI"),
				"include_system":     boolSchema("include system_info from the CyCom computer runtime"),
				"include_screenshot": boolSchema("when include_app is true, also request screenshot data; requires screen.capture permission"),
				"known_digest":       stringSchema("optional contextDigest from a previous desktop_get_context response; matching context returns a compact unchanged response"),
				"known_sections": map[string]any{
					"type":                 "object",
					"description":          "optional sectionDigests from a previous response; unchanged sections are omitted from the new payload",
					"additionalProperties": map[string]any{"type": "string"},
				},
			}, nil),
			Annotations: map[string]any{"readOnlyHint": true},
			Source:      contextToolSource,
			Handler: func(ctx context.Context, raw json.RawMessage) (any, error) {
				var args struct {
					IncludeApp        bool              `json:"include_app"`
					IncludeSystem     bool              `json:"include_system"`
					IncludeScreenshot bool              `json:"include_screenshot"`
					KnownDigest       string            `json:"known_digest"`
					KnownSections     map[string]string `json:"known_sections"`
				}
				if len(raw) > 0 {
					_ = json.Unmarshal(raw, &args)
				}

				desktopRaw, err := callShellIPC("agent", "state", nil)
				if err != nil {
					return nil, err
				}
				contextGraph := map[string]any{
					"schemaVersion": 2,
					"shell":         "CyShell Desktop",
					"desktop":       decodeJSONOrString(desktopRaw),
					"permissions":   manager.Permissions(),
					"capabilities": map[string]any{
						"semanticShell": true,
						"anyApp":        manager.hasTool("anyapp_get_app_state"),
						"screenCapture": manager.hasTool("anyapp_screenshot") || manager.hasTool("desktop_capture"),
					},
				}

				if args.IncludeApp {
					focused, err := manager.callRuntime(ctx, "anyapp_focused_window", map[string]any{
						"reason": "Build the unified CyShell desktop context for the focused application",
					})
					if err != nil {
						contextGraph["appError"] = err.Error()
					} else {
						contextGraph["focusedAppWindow"] = focused
					}

					app, err := manager.callRuntime(ctx, "anyapp_get_app_state", map[string]any{
						"include_screenshot": args.IncludeScreenshot,
						"reason":             "Build the unified CyShell desktop context for the focused application",
					})
					if err != nil {
						contextGraph["appStateError"] = err.Error()
					} else {
						contextGraph["app"] = app
					}
				}

				if args.IncludeSystem {
					system, err := manager.callRuntime(ctx, "system_info", map[string]any{
						"reason": "Build the unified CyShell desktop context with system information",
					})
					if err != nil {
						contextGraph["systemError"] = err.Error()
					} else {
						contextGraph["system"] = system
					}
				}
				return finalizeDesktopContext(contextGraph, args.KnownDigest, args.KnownSections)
			},
		},
		{
			Name:        "app_query_ui",
			Title:       "Query another application's semantic UI",
			Description: "Read a third-party application's accessibility tree through Any App / AT-SPI and return semantic matches. Screenshots are off by default and are only included when explicitly requested.",
			InputSchema: objectSchema(map[string]any{
				"query":              stringSchema("case-insensitive text matched against role, name, text, description, states and actions; empty returns the compact app state"),
				"app_id":             stringSchema("optional application id selector"),
				"title":              stringSchema("optional window title selector"),
				"pid":                integerSchema("optional process id selector"),
				"window_id":          integerSchema("optional compositor window id selector"),
				"max_nodes":          integerSchema("maximum accessibility nodes to inspect"),
				"include_screenshot": boolSchema("include screenshot data; requires screen.capture permission"),
			}, nil),
			Annotations: map[string]any{"readOnlyHint": true},
			Source:      contextToolSource,
			Handler: func(ctx context.Context, raw json.RawMessage) (any, error) {
				var args map[string]any
				if len(raw) > 0 {
					if err := json.Unmarshal(raw, &args); err != nil {
						return nil, err
					}
				}
				if args == nil {
					args = map[string]any{}
				}
				query, _ := args["query"].(string)
				maxResults := 60
				if rawMax, ok := args["max_nodes"].(float64); ok && rawMax > 0 {
					maxResults = int(rawMax)
				}
				delete(args, "query")
				args["reason"] = "Read another application's semantic UI for the CyShell Agent"
				if _, ok := args["include_screenshot"]; !ok {
					args["include_screenshot"] = false
				}
				state, err := manager.callRuntime(ctx, "anyapp_get_app_state", args)
				if err != nil {
					return nil, err
				}
				return semanticAppQueryResult(state, query, maxResults), nil
			},
		},
		{
			Name:        "desktop_query",
			Title:       "Query the semantic desktop",
			Description: "Query CyShell and third-party application semantics through one API. In auto mode CyShell is searched first and the focused application's AT-SPI tree is searched as a fallback when there are no shell matches.",
			InputSchema: objectSchema(map[string]any{
				"query":       stringSchema("semantic text to find"),
				"scope":       enumSchema("query scope", "auto", "shell", "app"),
				"max_results": integerSchema("maximum semantic matches returned from each scope; defaults to 40 and is capped at 200"),
			}, []string{"query"}),
			Annotations: map[string]any{"readOnlyHint": true},
			Source:      contextToolSource,
			Handler: func(ctx context.Context, raw json.RawMessage) (any, error) {
				var args struct {
					Query      string `json:"query"`
					Scope      string `json:"scope"`
					MaxResults int    `json:"max_results"`
				}
				if err := json.Unmarshal(raw, &args); err != nil {
					return nil, err
				}
				args.Query = strings.TrimSpace(args.Query)
				if args.Query == "" {
					return nil, errors.New("query is required")
				}
				if args.Scope == "" {
					args.Scope = "auto"
				}
				if args.MaxResults <= 0 {
					args.MaxResults = 40
				}
				if args.MaxResults > 200 {
					args.MaxResults = 200
				}

				result := map[string]any{"query": args.Query, "scope": args.Scope, "maxResults": args.MaxResults}
				if args.Scope == "auto" || args.Scope == "shell" {
					shellRaw, err := callShellIPC("agent", "queryUi", []string{args.Query})
					if err != nil {
						if args.Scope == "shell" {
							return nil, err
						}
						result["shellError"] = err.Error()
					} else {
						shellMatches := rankSemanticNodes(decodeJSONOrString(shellRaw), args.Query, args.MaxResults)
						result["shell"] = shellMatches
						if args.Scope == "auto" && semanticResultHasMatches(shellMatches) {
							result["resolvedBy"] = "shell"
							return result, nil
						}
					}
				}
				if args.Scope == "auto" || args.Scope == "app" {
					app, err := manager.callRuntime(ctx, "app_query_ui", map[string]any{
						"query":              args.Query,
						"max_nodes":          args.MaxResults,
						"include_screenshot": false,
						"reason":             "Search the focused application's semantic UI after querying CyShell",
					})
					if err != nil {
						if args.Scope == "app" {
							return nil, err
						}
						result["appError"] = err.Error()
					} else {
						result["app"] = app
						result["resolvedBy"] = "app"
					}
				}
				return result, nil
			},
		},
		{
			Name:        "desktop_action",
			Title:       "Control semantic desktop state",
			Description: "Perform a native CyShell machine action without shell commands or raw input. Supports Wi-Fi and Bluetooth radio control, output/input volume, mute, brightness, and power profile. Read back desktop_get_context after state changes when verification matters.",
			InputSchema: objectSchema(map[string]any{
				"action": enumSchema("semantic machine action", "wifi.toggle", "wifi.enable", "wifi.disable", "bluetooth.toggle", "bluetooth.enable", "bluetooth.disable", "audio.volume.set", "audio.mute.toggle", "audio.mute.set", "mic.volume.set", "mic.mute.toggle", "mic.mute.set", "brightness.set", "power.profile.set"),
				"value":  stringSchema("optional action value, such as 50 for volume/brightness or balanced for power profile"),
			}, []string{"action"}),
			Source: contextToolSource,
			Handler: func(_ context.Context, raw json.RawMessage) (any, error) {
				var args struct {
					Action string `json:"action"`
					Value  string `json:"value"`
				}
				if err := json.Unmarshal(raw, &args); err != nil {
					return nil, err
				}
				args.Action = strings.TrimSpace(args.Action)
				if args.Action == "" {
					return nil, errors.New("action is required")
				}
				var undoAction, undoValue string
				undoable := false
				undoCaptureError := ""
				if stateRaw, stateErr := callShellIPC("agent", "state", nil); stateErr == nil {
					undoAction, undoValue, undoable = desktopUndoFromState(args.Action, decodeJSONOrString(stateRaw))
				} else {
					undoCaptureError = stateErr.Error()
				}

				result, err := executeMachineAction(args.Action, args.Value)
				if err != nil {
					return nil, err
				}
				response := map[string]any{"success": true, "action": args.Action, "value": args.Value, "result": result}
				if undoable {
					receipt := manager.issueActionReceipt(args.Action, args.Value, undoAction, undoValue)
					response["receipt"] = receipt
				} else if undoCaptureError != "" {
					response["undoUnavailable"] = compactActivityError(undoCaptureError)
				}
				return response, nil
			},
		},
		{
			Name:        "desktop_receipts",
			Title:       "List undoable desktop actions",
			Description: "List unexpired session-bound semantic action receipts returned by reversible Agent actions such as desktop_action and shell_settings_set. Receipts expire automatically and contain no raw tool arguments.",
			InputSchema: objectSchema(nil, nil),
			Annotations: map[string]any{"readOnlyHint": true},
			Source:      contextToolSource,
			Handler: func(_ context.Context, _ json.RawMessage) (any, error) {
				return map[string]any{"receipts": manager.ActionReceipts()}, nil
			},
		},
		{
			Name:        "desktop_undo",
			Title:       "Undo a semantic desktop action",
			Description: "Rollback one unexpired semantic action receipt to its captured pre-action state. Machine controls and scalar CyShell settings are supported. The receipt is consumed only after rollback succeeds.",
			InputSchema: objectSchema(map[string]any{
				"receipt": stringSchema("action receipt id returned by desktop_action or desktop_receipts"),
			}, []string{"receipt"}),
			Source: contextToolSource,
			Handler: func(_ context.Context, raw json.RawMessage) (any, error) {
				var args struct {
					Receipt string `json:"receipt"`
				}
				if err := json.Unmarshal(raw, &args); err != nil {
					return nil, err
				}
				record, err := manager.actionReceiptForUndo(args.Receipt)
				if err != nil {
					return nil, err
				}
				result, err := executeReceiptUndo(record)
				if err != nil {
					return nil, fmt.Errorf("rollback %s: %w", record.Receipt.ID, err)
				}
				manager.consumeActionReceipt(record.Receipt.ID)
				return map[string]any{
					"success":  true,
					"receipt":  record.Receipt,
					"rollback": map[string]any{"action": record.UndoAction, "value": record.UndoValue, "result": result},
				}, nil
			},
		},
	}

	for _, tool := range tools {
		if err := manager.runtime.RegisterTool(tool); err != nil {
			return fmt.Errorf("register %s: %w", tool.Name, err)
		}
	}
	return nil
}

func executeMachineAction(action, value string) (string, error) {
	result, err := callShellIPC("agent", "machineAction", []string{strings.TrimSpace(action), strings.TrimSpace(value)})
	if err != nil {
		return "", err
	}
	if strings.Contains(result, "UNSUPPORTED") || strings.Contains(result, "INVALID") || strings.Contains(result, "FAILED") || strings.HasPrefix(result, "ERROR") {
		return "", errors.New(result)
	}
	return result, nil
}

func (m *Manager) hasTool(name string) bool {
	for _, tool := range m.runtime.ListTools() {
		if tool.Name == name {
			return true
		}
	}
	return false
}

func (m *Manager) callRuntime(ctx context.Context, name string, args map[string]any) (any, error) {
	if !m.hasTool(name) {
		return nil, fmt.Errorf("CyCom tool %s is unavailable", name)
	}
	raw, err := json.Marshal(args)
	if err != nil {
		return nil, err
	}
	value, err := m.runtime.Call(ctx, name, raw)
	if err != nil {
		return nil, err
	}
	return normalizeRuntimeResult(value), nil
}

func normalizeRuntimeResult(value any) any {
	data, err := json.Marshal(value)
	if err != nil {
		return value
	}
	var decoded any
	if json.Unmarshal(data, &decoded) != nil {
		return value
	}
	if object, ok := decoded.(map[string]any); ok {
		if structured, exists := object["structured"]; exists && structured != nil {
			return structured
		}
	}
	return decoded
}

func finalizeDesktopContext(contextGraph map[string]any, knownDigest string, knownSections map[string]string) (map[string]any, error) {
	if contextGraph == nil {
		contextGraph = map[string]any{}
	}
	sectionDigests := map[string]string{}
	for key, value := range contextGraph {
		if !desktopContextSection(key) {
			continue
		}
		digest, err := stableJSONDigest(value)
		if err != nil {
			return nil, err
		}
		sectionDigests[key] = digest
	}

	payload := make(map[string]any, len(contextGraph))
	for key, value := range contextGraph {
		payload[key] = value
	}
	fullDigest, err := stableJSONDigest(payload)
	if err != nil {
		return nil, err
	}

	if strings.TrimSpace(knownDigest) != "" && strings.TrimSpace(knownDigest) == fullDigest {
		return map[string]any{
			"schemaVersion":  contextGraph["schemaVersion"],
			"shell":          contextGraph["shell"],
			"contextDigest":  fullDigest,
			"sectionDigests": sectionDigests,
			"unchanged":      true,
		}, nil
	}

	result := make(map[string]any, len(contextGraph)+4)
	for key, value := range contextGraph {
		result[key] = value
	}
	unchangedSections := make([]string, 0)
	for key, known := range knownSections {
		current, ok := sectionDigests[key]
		if !ok || strings.TrimSpace(known) == "" || strings.TrimSpace(known) != current {
			continue
		}
		delete(result, key)
		unchangedSections = append(unchangedSections, key)
	}
	sort.Strings(unchangedSections)
	result["contextDigest"] = fullDigest
	result["sectionDigests"] = sectionDigests
	result["unchanged"] = false
	if len(unchangedSections) > 0 {
		result["unchangedSections"] = unchangedSections
	}
	return result, nil
}

func desktopContextSection(key string) bool {
	switch key {
	case "desktop", "permissions", "capabilities", "focusedAppWindow", "app", "appError", "appStateError", "system", "systemError":
		return true
	default:
		return false
	}
}

func stableJSONDigest(value any) (string, error) {
	data, err := json.Marshal(value)
	if err != nil {
		return "", fmt.Errorf("encode desktop context digest: %w", err)
	}
	sum := sha256.Sum256(data)
	return fmt.Sprintf("sha256:%x", sum), nil
}

func semanticAppQueryResult(state any, query string, maxResults int) any {
	query = strings.TrimSpace(query)
	if maxResults < 1 {
		maxResults = 60
	}
	if maxResults > 200 {
		maxResults = 200
	}
	object, ok := state.(map[string]any)
	if !ok {
		return map[string]any{
			"projectionVersion": 1,
			"query":             query,
			"state":             state,
		}
	}

	rawTree := firstAccessibilityTree(object)
	flat := make([]map[string]any, 0, 128)
	walkAccessibility(rawTree, &flat)
	projected := make([]map[string]any, 0, len(flat))
	for _, node := range flat {
		compact := projectAccessibilityNode(node)
		if len(compact) == 0 {
			continue
		}
		if query != "" && !nodeMatchesQuery(compact, query) {
			continue
		}
		if query == "" && !interestingAccessibilityNode(compact) {
			continue
		}
		projected = append(projected, compact)
	}
	projected = collapseRepeatedNodes(projected)
	totalMatches := len(projected)
	truncated := totalMatches > maxResults
	if truncated {
		projected = projected[:maxResults]
	}

	result := map[string]any{
		"projectionVersion": 1,
		"query":             query,
		"sourceNodeCount":   len(flat),
		"matchCount":        totalMatches,
		"returnedCount":     len(projected),
		"truncated":         truncated,
		"matches":           projected,
	}
	for _, key := range []string{"backend", "message", "readiness", "window_context", "accessibility_error", "window_error"} {
		if value, exists := object[key]; exists {
			result[key] = value
		}
	}
	if screenshot, exists := object["screenshot"]; exists && screenshot != nil {
		result["screenshot"] = screenshot
	}
	return result
}

func firstAccessibilityTree(object map[string]any) any {
	for _, key := range []string{"accessibility_tree", "accessibilityTree", "tree", "nodes"} {
		if value, ok := object[key]; ok && value != nil {
			return value
		}
	}
	return nil
}

func walkAccessibility(value any, out *[]map[string]any) {
	switch node := value.(type) {
	case []any:
		for _, child := range node {
			walkAccessibility(child, out)
		}
	case map[string]any:
		if looksLikeAccessibilityNode(node) {
			*out = append(*out, node)
		}
		for _, key := range []string{"children", "nodes", "items", "descendants"} {
			if child, ok := node[key]; ok {
				walkAccessibility(child, out)
			}
		}
	}
}

func looksLikeAccessibilityNode(node map[string]any) bool {
	for _, key := range []string{"role", "name", "text", "actions", "path", "index", "description"} {
		if _, ok := node[key]; ok {
			return true
		}
	}
	return false
}

func projectAccessibilityNode(node map[string]any) map[string]any {
	out := map[string]any{}
	for _, key := range []string{
		"index", "path", "role", "name", "text", "description", "value", "states", "actions",
		"focused", "selected", "checked", "enabled", "editable", "shortcut", "bounds", "rect",
	} {
		if value, ok := node[key]; ok && meaningfulValue(value) {
			out[key] = compactValue(value)
		}
	}
	return out
}

func meaningfulValue(value any) bool {
	switch v := value.(type) {
	case nil:
		return false
	case string:
		return strings.TrimSpace(v) != ""
	case []any:
		return len(v) > 0
	case map[string]any:
		return len(v) > 0
	default:
		return true
	}
}

func compactValue(value any) any {
	switch v := value.(type) {
	case string:
		v = strings.Join(strings.Fields(v), " ")
		if len(v) > 320 {
			return v[:320] + "…"
		}
		return v
	case []any:
		if len(v) > 12 {
			return append([]any(nil), v[:12]...)
		}
	}
	return value
}

func nodeMatchesQuery(node map[string]any, query string) bool {
	query = strings.ToLower(strings.Join(strings.Fields(query), " "))
	if query == "" {
		return true
	}
	data, _ := json.Marshal(node)
	haystack := strings.ToLower(string(data))
	if strings.Contains(haystack, query) {
		return true
	}
	for _, term := range strings.Fields(query) {
		if !strings.Contains(haystack, term) {
			return false
		}
	}
	return true
}

func interestingAccessibilityNode(node map[string]any) bool {
	if meaningfulValue(node["actions"]) || meaningfulValue(node["text"]) || meaningfulValue(node["name"]) {
		return true
	}
	role := strings.ToLower(fmt.Sprint(node["role"]))
	switch role {
	case "button", "checkbox", "combobox", "entry", "link", "menuitem", "radio", "slider", "switch", "tab", "textbox", "togglebutton":
		return true
	default:
		return false
	}
}

func collapseRepeatedNodes(nodes []map[string]any) []map[string]any {
	if len(nodes) < 2 {
		return nodes
	}
	out := make([]map[string]any, 0, len(nodes))
	lastSig := ""
	for _, node := range nodes {
		sig := accessibilityNodeSignature(node)
		if sig != "" && sig == lastSig && len(out) > 0 {
			count := 1
			if existing, ok := out[len(out)-1]["repeatCount"].(int); ok {
				count = existing
			} else if existing, ok := out[len(out)-1]["repeatCount"].(float64); ok {
				count = int(existing)
			}
			out[len(out)-1]["repeatCount"] = count + 1
			continue
		}
		copyNode := make(map[string]any, len(node)+1)
		for key, value := range node {
			copyNode[key] = value
		}
		out = append(out, copyNode)
		lastSig = sig
	}
	return out
}

func accessibilityNodeSignature(node map[string]any) string {
	parts := []string{
		fmt.Sprint(node["role"]),
		fmt.Sprint(node["name"]),
		fmt.Sprint(node["text"]),
		fmt.Sprint(node["description"]),
		fmt.Sprint(node["actions"]),
	}
	return strings.ToLower(strings.Join(parts, "|"))
}

func semanticResultHasMatches(value any) bool {
	items, ok := value.([]any)
	return ok && len(items) > 0
}

func boolSchema(description string) map[string]any {
	return map[string]any{"type": "boolean", "description": description}
}

func integerSchema(description string) map[string]any {
	return map[string]any{"type": "integer", "minimum": 0, "description": description}
}
