package cycom

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const approvalTimeout = 2 * time.Minute

type AppPolicyState struct {
	AppKey      string            `json:"appKey"`
	AppName     string            `json:"appName"`
	Permissions map[string]string `json:"permissions"`
}

type ApprovalRequest struct {
	ID          string   `json:"id"`
	AppKey      string   `json:"appKey"`
	AppName     string   `json:"appName"`
	Scopes      []string `json:"scopes"`
	Tool        string   `json:"tool"`
	Reason      string   `json:"reason,omitempty"`
	CreatedAt   int64    `json:"createdAt"`
	ExpiresAt   int64    `json:"expiresAt"`
	CanRemember bool     `json:"canRemember"`
}

type appPolicyConfig struct {
	Name        string            `json:"name"`
	Permissions map[string]string `json:"permissions"`
}

type approvalDecision struct {
	allow bool
	err   error
}

type pendingApproval struct {
	request  ApprovalRequest
	decision chan approvalDecision
	once     sync.Once
}

func sensitiveAppScope(scope string) bool {
	switch scope {
	case "app.read", "app.control", "screen.capture":
		return true
	default:
		return false
	}
}

func normalizePolicyMode(mode string) (string, bool) {
	switch strings.ToLower(strings.TrimSpace(mode)) {
	case "allow":
		return "allow", true
	case "deny":
		return "deny", true
	case "ask", "":
		return "ask", true
	default:
		return "", false
	}
}

func (m *Manager) AppPolicies() []AppPolicyState {
	m.appPoliciesMu.RLock()
	defer m.appPoliciesMu.RUnlock()
	items := make([]AppPolicyState, 0, len(m.appPolicies))
	for key, cfg := range m.appPolicies {
		permissions := make(map[string]string, len(cfg.Permissions))
		for scope, mode := range cfg.Permissions {
			permissions[scope] = mode
		}
		items = append(items, AppPolicyState{AppKey: key, AppName: cfg.Name, Permissions: permissions})
	}
	sort.Slice(items, func(i, j int) bool {
		if items[i].AppName != items[j].AppName {
			return strings.ToLower(items[i].AppName) < strings.ToLower(items[j].AppName)
		}
		return items[i].AppKey < items[j].AppKey
	})
	return items
}

func (m *Manager) SetAppPolicy(appKey, appName, scope, mode string) error {
	appKey = strings.TrimSpace(appKey)
	if appKey == "" {
		return errors.New("appKey is required")
	}
	if !sensitiveAppScope(scope) {
		return fmt.Errorf("scope %q does not support per-app policy", scope)
	}
	normalized, ok := normalizePolicyMode(mode)
	if !ok {
		return fmt.Errorf("invalid app policy mode %q", mode)
	}
	m.appPoliciesMu.Lock()
	cfg := m.appPolicies[appKey]
	if cfg.Permissions == nil {
		cfg.Permissions = map[string]string{}
	}
	if strings.TrimSpace(appName) != "" {
		cfg.Name = strings.TrimSpace(appName)
	}
	if normalized == "ask" {
		delete(cfg.Permissions, scope)
	} else {
		cfg.Permissions[scope] = normalized
	}
	if len(cfg.Permissions) == 0 {
		delete(m.appPolicies, appKey)
	} else {
		m.appPolicies[appKey] = cfg
	}
	m.appPoliciesMu.Unlock()
	m.cancelActiveCalls()
	err := m.persistControl()
	m.broadcastState()
	return err
}

func (m *Manager) ClearAppPolicy(appKey string) error {
	appKey = strings.TrimSpace(appKey)
	if appKey == "" {
		return errors.New("appKey is required")
	}
	m.appPoliciesMu.Lock()
	delete(m.appPolicies, appKey)
	m.appPoliciesMu.Unlock()
	m.cancelActiveCalls()
	err := m.persistControl()
	m.broadcastState()
	return err
}

func (m *Manager) appPolicyMode(appKey, scope string) string {
	m.appPoliciesMu.RLock()
	defer m.appPoliciesMu.RUnlock()
	if cfg, ok := m.appPolicies[appKey]; ok {
		if mode, ok := cfg.Permissions[scope]; ok {
			return mode
		}
	}
	return "ask"
}

func (m *Manager) PendingApprovals() []ApprovalRequest {
	m.approvalsMu.Lock()
	defer m.approvalsMu.Unlock()
	items := make([]ApprovalRequest, 0, len(m.pendingApprovals))
	for _, pending := range m.pendingApprovals {
		if pending != nil {
			items = append(items, pending.request)
		}
	}
	sort.Slice(items, func(i, j int) bool { return items[i].CreatedAt < items[j].CreatedAt })
	return items
}

func (m *Manager) RespondApproval(id, decision string) error {
	m.approvalsMu.Lock()
	pending := m.pendingApprovals[id]
	m.approvalsMu.Unlock()
	if pending == nil {
		return fmt.Errorf("approval %q is not pending", id)
	}

	decision = strings.ToLower(strings.TrimSpace(decision))
	remember := decision == "allow_always" || decision == "deny_always"
	allow := decision == "allow_once" || decision == "allow_always"
	if decision != "allow_once" && decision != "allow_always" && decision != "deny_once" && decision != "deny_always" {
		return fmt.Errorf("invalid approval decision %q", decision)
	}
	if remember && !pending.request.CanRemember {
		return errors.New("this approval target cannot be remembered safely")
	}
	if remember {
		mode := "deny"
		if allow {
			mode = "allow"
		}
		for _, scope := range pending.request.Scopes {
			if err := m.setAppPolicyWithoutCancel(pending.request.AppKey, pending.request.AppName, scope, mode); err != nil {
				return err
			}
		}
		if err := m.persistControl(); err != nil {
			return err
		}
	}
	pending.once.Do(func() {
		pending.decision <- approvalDecision{allow: allow}
	})
	return nil
}

func (m *Manager) setAppPolicyWithoutCancel(appKey, appName, scope, mode string) error {
	if !sensitiveAppScope(scope) {
		return fmt.Errorf("scope %q does not support per-app policy", scope)
	}
	m.appPoliciesMu.Lock()
	defer m.appPoliciesMu.Unlock()
	cfg := m.appPolicies[appKey]
	if cfg.Permissions == nil {
		cfg.Permissions = map[string]string{}
	}
	if strings.TrimSpace(appName) != "" {
		cfg.Name = strings.TrimSpace(appName)
	}
	cfg.Permissions[scope] = mode
	m.appPolicies[appKey] = cfg
	return nil
}

func appApprovalRelevantTool(name string) bool {
	switch name {
	case "anyapp_get_app_state", "anyapp_click", "anyapp_drag", "anyapp_perform_action", "anyapp_press_key", "anyapp_scroll", "anyapp_set_value", "anyapp_type_text", "anyapp_screenshot", "desktop_capture", "desktop_input":
		return true
	default:
		return false
	}
}

func (m *Manager) checkAppApprovals(ctx context.Context, name string, raw json.RawMessage) error {
	if !appApprovalRelevantTool(name) {
		return nil
	}
	scopes := m.requiredScopes(name, raw)
	sensitive := make([]string, 0, len(scopes))
	for _, scope := range scopes {
		if sensitiveAppScope(scope) {
			sensitive = append(sensitive, scope)
		}
	}
	if len(sensitive) == 0 {
		return nil
	}

	target := m.resolveApprovalTarget(name, raw)
	needsAsk := make([]string, 0, len(sensitive))
	for _, scope := range sensitive {
		mode := m.appPolicyMode(target.key, scope)
		switch mode {
		case "allow":
			continue
		case "deny":
			return fmt.Errorf("CyShell Agent per-app policy denies %s for %s", scope, target.name)
		default:
			needsAsk = append(needsAsk, scope)
		}
	}
	if len(needsAsk) == 0 {
		return nil
	}
	return m.awaitApproval(ctx, target, name, raw, needsAsk)
}

type approvalTarget struct {
	key         string
	name        string
	canRemember bool
}

func (m *Manager) resolveApprovalTarget(tool string, raw json.RawMessage) approvalTarget {
	if tool == "desktop_capture" || tool == "anyapp_screenshot" {
		if tool == "desktop_capture" {
			return approvalTarget{key: "screen:desktop", name: "Desktop screen", canRemember: true}
		}
	}
	var args map[string]any
	_ = json.Unmarshal(raw, &args)
	if nested, ok := args["selector"].(map[string]any); ok {
		for key, value := range nested {
			if _, exists := args[key]; !exists {
				args[key] = value
			}
		}
	}
	if appID := firstString(args, "app_id", "appId", "application", "wmClass"); appID != "" {
		return approvalTarget{key: "app:" + strings.ToLower(appID), name: appID, canRemember: true}
	}
	if pid := firstInt(args, "pid"); pid > 0 {
		return approvalTarget{key: "pid:" + strconv.Itoa(pid), name: "PID " + strconv.Itoa(pid), canRemember: false}
	}
	if title := firstString(args, "title"); title != "" {
		return approvalTarget{key: "title:" + strings.ToLower(title), name: title, canRemember: false}
	}

	stateRaw, err := callShellIPC("agent", "state", nil)
	if err == nil {
		if state, ok := decodeJSONOrString(stateRaw).(map[string]any); ok {
			if active, ok := state["activeWindow"].(map[string]any); ok {
				if appID, _ := active["appId"].(string); strings.TrimSpace(appID) != "" {
					name := strings.TrimSpace(appID)
					if title, _ := active["title"].(string); strings.TrimSpace(title) != "" {
						name = strings.TrimSpace(title)
					}
					return approvalTarget{key: "app:" + strings.ToLower(strings.TrimSpace(appID)), name: name, canRemember: true}
				}
				if title, _ := active["title"].(string); strings.TrimSpace(title) != "" {
					return approvalTarget{key: "title:" + strings.ToLower(strings.TrimSpace(title)), name: strings.TrimSpace(title), canRemember: false}
				}
			}
		}
	}
	if containsScope(m.requiredScopes(tool, raw), "screen.capture") {
		return approvalTarget{key: "screen:desktop", name: "Desktop screen", canRemember: true}
	}
	return approvalTarget{key: "app:focused", name: "Focused application", canRemember: false}
}

func firstString(values map[string]any, keys ...string) string {
	for _, key := range keys {
		if value, ok := values[key].(string); ok && strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func firstInt(values map[string]any, keys ...string) int {
	for _, key := range keys {
		switch value := values[key].(type) {
		case float64:
			return int(value)
		case int:
			return value
		case json.Number:
			parsed, _ := strconv.Atoi(value.String())
			return parsed
		}
	}
	return 0
}

func containsScope(scopes []string, wanted string) bool {
	for _, scope := range scopes {
		if scope == wanted {
			return true
		}
	}
	return false
}

func (m *Manager) awaitApproval(ctx context.Context, target approvalTarget, tool string, raw json.RawMessage, scopes []string) error {
	now := time.Now()
	id := fmt.Sprintf("approval-%d", m.approvalID.Add(1))
	reason := ""
	var args map[string]any
	if json.Unmarshal(raw, &args) == nil {
		reason, _ = args["reason"].(string)
	}
	pending := &pendingApproval{
		request: ApprovalRequest{
			ID:          id,
			AppKey:      target.key,
			AppName:     target.name,
			Scopes:      append([]string(nil), scopes...),
			Tool:        tool,
			Reason:      strings.TrimSpace(reason),
			CreatedAt:   now.UnixMilli(),
			ExpiresAt:   now.Add(approvalTimeout).UnixMilli(),
			CanRemember: target.canRemember,
		},
		decision: make(chan approvalDecision, 1),
	}
	m.approvalsMu.Lock()
	m.pendingApprovals[id] = pending
	m.approvalsMu.Unlock()
	m.broadcastState()
	defer func() {
		m.approvalsMu.Lock()
		delete(m.pendingApprovals, id)
		m.approvalsMu.Unlock()
		m.broadcastState()
	}()

	timer := time.NewTimer(approvalTimeout)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return fmt.Errorf("approval timed out for %s", target.name)
	case decision := <-pending.decision:
		if decision.err != nil {
			return decision.err
		}
		if !decision.allow {
			return fmt.Errorf("user denied %s for %s", strings.Join(scopes, ", "), target.name)
		}
		return nil
	}
}
