package cycom

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/AvengeMedia/dankgo/ipc"
	cycomembed "github.com/Cytech-Team/CyComAgent-MCP/embed"
	"github.com/Cytech-Team/CyShell-Desktop/core/internal/server/models"
)

type Manager struct {
	runtime   *cycomembed.Runtime
	assistant *Assistant

	enabled               atomic.Bool
	controlEnabled        atomic.Bool
	agentWorkspaceEnabled atomic.Bool
	useAgentWorkspace     atomic.Bool
	workspaceMu           sync.RWMutex
	agentWorkspaceWidth   int
	agentWorkspaceHeight  int
	agentWorkspaceRefresh float64
	agentWorkspaceScale   float64
	callID                atomic.Uint64
	activeMu              sync.Mutex
	activeCalls           map[uint64]context.CancelFunc
	controlPath           string
	integrationClientMu   sync.Mutex
	permissionsMu         sync.RWMutex
	permissions           map[string]bool
	appPoliciesMu         sync.RWMutex
	appPolicies           map[string]appPolicyConfig
	sessionAppAllows      map[string]map[string]bool
	approvalModeMu        sync.RWMutex
	approvalMode          string
	approvalID            atomic.Uint64
	approvalsMu           sync.Mutex
	pendingApprovals      map[string]*pendingApproval
	activityID            atomic.Uint64
	activityMu            sync.Mutex
	recentActivity        []Activity
	eventsMu              sync.Mutex
	eventSubscribers      map[string]chan Event
	receiptID             atomic.Uint64
	receiptsMu            sync.Mutex
	actionReceipts        map[string]actionReceiptRecord
}

type State struct {
	Embedded              bool              `json:"embedded"`
	Enabled               bool              `json:"enabled"`
	ControlEnabled        bool              `json:"controlEnabled"`
	Version               string            `json:"version"`
	StateDir              string            `json:"stateDir"`
	ToolCount             int               `json:"toolCount"`
	ActiveCalls           int               `json:"activeCalls"`
	Permissions           []PermissionState `json:"permissions"`
	AppPolicies           []AppPolicyState  `json:"appPolicies"`
	ApprovalMode          string            `json:"approvalMode"`
	PendingApprovalCount  int               `json:"pendingApprovalCount"`
	UndoReceiptCount      int               `json:"undoReceiptCount"`
	AgentWorkspaceEnabled bool              `json:"agentWorkspaceEnabled"`
	AgentWorkspaceActive  bool              `json:"agentWorkspaceActive"`
	UseAgentWorkspace     bool              `json:"useAgentWorkspace"`
	AgentWorkspaceDisplay string            `json:"agentWorkspaceDisplay,omitempty"`
	AgentWorkspaceWidth   int               `json:"agentWorkspaceWidth"`
	AgentWorkspaceHeight  int               `json:"agentWorkspaceHeight"`
	AgentWorkspaceRefresh float64           `json:"agentWorkspaceRefresh"`
	AgentWorkspaceScale   float64           `json:"agentWorkspaceScale"`
	Assistant             AssistantState    `json:"assistant"`
}

type controlConfig struct {
	Version               int                        `json:"version"`
	Enabled               bool                       `json:"enabled"`
	ControlEnabled        bool                       `json:"controlEnabled"`
	ApprovalMode          string                     `json:"approvalMode,omitempty"`
	AgentWorkspaceEnabled bool                       `json:"agentWorkspaceEnabled,omitempty"`
	UseAgentWorkspace     bool                       `json:"useAgentWorkspace,omitempty"`
	AgentWorkspaceWidth   int                        `json:"agentWorkspaceWidth,omitempty"`
	AgentWorkspaceHeight  int                        `json:"agentWorkspaceHeight,omitempty"`
	AgentWorkspaceRefresh float64                    `json:"agentWorkspaceRefresh,omitempty"`
	AgentWorkspaceScale   float64                    `json:"agentWorkspaceScale,omitempty"`
	Permissions           map[string]bool            `json:"permissions,omitempty"`
	AppPolicies           map[string]appPolicyConfig `json:"appPolicies,omitempty"`
}

type runtimeGate struct{ manager *Manager }

func requestNumber(req ipc.Request, key string) (float64, bool) {
	if value, ok := models.Get[float64](req, key); ok {
		return value, true
	}
	if value, ok := models.Get[int](req, key); ok {
		return float64(value), true
	}
	if value, ok := models.Get[int64](req, key); ok {
		return float64(value), true
	}
	return 0, false
}

func (g runtimeGate) BeforeCall(ctx context.Context, name string, raw json.RawMessage) error {
	if g.manager == nil || !g.manager.enabled.Load() {
		return fmt.Errorf("CyShell Agent is disabled")
	}

	// Full access intentionally mirrors ChatGPT's unrestricted mode: once the
	// user selects it, normal scope toggles, per-app prompts and the master
	// computer-control gate are bypassed. Disabling the Agent still stops all
	// calls and remains the emergency kill switch.
	if g.manager.ApprovalMode() == approvalModeFull {
		return nil
	}

	if err := g.manager.checkPermissions(name, raw); err != nil {
		return err
	}
	if !g.manager.controlEnabled.Load() && !g.manager.toolReadOnly(name) {
		return fmt.Errorf("CyShell Agent control is disabled by the user")
	}
	if err := g.manager.checkGeneralApproval(ctx, name, raw); err != nil {
		return err
	}
	if err := g.manager.checkAppApprovals(ctx, name, raw); err != nil {
		return err
	}
	return nil
}

func (runtimeGate) AfterCall(context.Context, string, json.RawMessage, time.Duration, error) {}

func defaultStateDir() string {
	if xdg := os.Getenv("XDG_STATE_HOME"); xdg != "" {
		return filepath.Join(xdg, "cycomagent")
	}
	if home, err := os.UserHomeDir(); err == nil {
		return filepath.Join(home, ".local", "state", "cycomagent")
	}
	return ".cycomagent"
}

func NewManager() (*Manager, error) {
	stateDir := defaultStateDir()
	rt, err := cycomembed.New(cycomembed.Config{
		Version:       "cyshell-embedded",
		StateDir:      stateDir,
		DirectSession: true,
		Instructions:  "CyCom is embedded in CyShell Desktop. Prefer CyShell semantic desktop tools when available; use generic computer-runtime tools for filesystem, process, service, network, remote-target, and fallback GUI work.",
	})
	if err != nil {
		return nil, err
	}
	m := &Manager{
		runtime:          rt,
		activeCalls:      make(map[uint64]context.CancelFunc),
		controlPath:      filepath.Join(stateDir, "cyshell-agent-control.json"),
		permissions:      defaultPermissionMap(),
		appPolicies:      make(map[string]appPolicyConfig),
		sessionAppAllows: make(map[string]map[string]bool),
		approvalMode:     approvalModeAsk,
		pendingApprovals: make(map[string]*pendingApproval),
		recentActivity:   make([]Activity, 0, agentRecentActivityLimit),
		eventSubscribers: make(map[string]chan Event),
		actionReceipts:   make(map[string]actionReceiptRecord),
	}
	if err := m.loadControl(); err != nil {
		return nil, err
	}
	m.applyAgentWorkspaceEnvironment()
	_ = m.applyAgentWorkspaceDisplayConfig(false)
	rt.AddInterceptor(runtimeGate{manager: m})
	if err := registerShellTools(m); err != nil {
		return nil, fmt.Errorf("register CyShell native agent tools: %w", err)
	}
	if err := registerContextTools(m); err != nil {
		return nil, fmt.Errorf("register CyShell Agent Context tools: %w", err)
	}
	m.assistant = NewAssistant(m)
	return m, nil
}

func (m *Manager) RuntimeState() State {
	m.activeMu.Lock()
	active := len(m.activeCalls)
	m.activeMu.Unlock()
	pending := len(m.PendingApprovals())
	receipts := len(m.ActionReceipts())
	workspaceActive, workspaceDisplay := m.AgentWorkspaceStatus()
	workspaceWidth, workspaceHeight, workspaceRefresh, workspaceScale := m.AgentWorkspaceDisplayConfig()
	return State{
		Embedded:              true,
		Enabled:               m.enabled.Load(),
		ControlEnabled:        m.controlEnabled.Load(),
		Version:               m.runtime.Version(),
		StateDir:              m.runtime.StateDir(),
		ToolCount:             len(m.runtime.ListTools()),
		ActiveCalls:           active,
		Permissions:           m.Permissions(),
		AppPolicies:           m.AppPolicies(),
		ApprovalMode:          m.ApprovalMode(),
		PendingApprovalCount:  pending,
		UndoReceiptCount:      receipts,
		AgentWorkspaceEnabled: m.agentWorkspaceEnabled.Load(),
		AgentWorkspaceActive:  workspaceActive,
		UseAgentWorkspace:     m.useAgentWorkspace.Load(),
		AgentWorkspaceDisplay: workspaceDisplay,
		AgentWorkspaceWidth:   workspaceWidth,
		AgentWorkspaceHeight:  workspaceHeight,
		AgentWorkspaceRefresh: workspaceRefresh,
		AgentWorkspaceScale:   workspaceScale,
	}
}

func (m *Manager) State() State {
	state := m.RuntimeState()
	if m.assistant != nil {
		state.Assistant = m.assistant.State()
	}
	return state
}

func HandleRequest(ctx context.Context, conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	switch req.Method {
	case "cycom.getState":
		models.Respond(conn, req.ID, manager.State())
	case "cycom.getRuntimeState":
		models.Respond(conn, req.ID, manager.RuntimeState())
	case "cycom.integration.get":
		models.Respond(conn, req.ID, manager.IntegrationState())
	case "cycom.integration.configure":
		mode, _ := models.Get[string](req, "mode")
		externalFallback, _ := models.Get[bool](req, "externalFallback")
		agentAppEnabled, _ := models.Get[bool](req, "agentAppEnabled")
		tunnelID, _ := models.Get[string](req, "tunnelId")
		tunnelAPIKey, _ := models.Get[string](req, "tunnelApiKey")
		clearTunnelCredentials, _ := models.Get[bool](req, "clearTunnelCredentials")
		state, err := manager.ConfigureIntegration(
			mode,
			externalFallback,
			agentAppEnabled,
			tunnelID,
			tunnelAPIKey,
			clearTunnelCredentials,
		)
		if err != nil {
			models.RespondError(conn, req.ID, err.Error())
			return
		}
		models.Respond(conn, req.ID, state)
	case "cycom.integration.client.set":
		clientID, ok := models.Get[string](req, "clientId")
		if !ok || strings.TrimSpace(clientID) == "" {
			models.RespondError(conn, req.ID, "clientId is required")
			return
		}
		connected, ok := models.Get[bool](req, "connected")
		if !ok {
			models.RespondError(conn, req.ID, "connected is required")
			return
		}
		state, err := manager.SetAgentClientConnected(clientID, connected)
		if err != nil {
			models.RespondError(conn, req.ID, err.Error())
			return
		}
		models.Respond(conn, req.ID, state)
	case "cycom.activity.list":
		models.Respond(conn, req.ID, manager.RecentActivity())
	case "cycom.activity.clear":
		manager.ClearRecentActivity()
		models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "Agent recent activity cleared"})
	case "cycom.receipts.list":
		models.Respond(conn, req.ID, manager.ActionReceipts())
	case "cycom.tools.list":
		models.Respond(conn, req.ID, manager.runtime.ListTools())
	case "cycom.tools.call":
		handleToolCall(ctx, conn, req, manager)
	case "cycom.setEnabled":
		enabled, ok := models.Get[bool](req, "enabled")
		if !ok {
			models.RespondError(conn, req.ID, "enabled is required")
			return
		}
		if err := manager.SetEnabled(enabled); err != nil {
			models.RespondError(conn, req.ID, err.Error())
			return
		}
		models.Respond(conn, req.ID, manager.State())
	case "cycom.setControlEnabled":
		enabled, ok := models.Get[bool](req, "enabled")
		if !ok {
			models.RespondError(conn, req.ID, "enabled is required")
			return
		}
		if err := manager.SetControlEnabled(enabled); err != nil {
			models.RespondError(conn, req.ID, err.Error())
			return
		}
		models.Respond(conn, req.ID, manager.State())
	case "cycom.agentWorkspace.setEnabled":
		enabled, ok := models.Get[bool](req, "enabled")
		if !ok {
			models.RespondError(conn, req.ID, "enabled is required")
			return
		}
		if err := manager.SetAgentWorkspaceEnabled(enabled); err != nil {
			models.RespondError(conn, req.ID, err.Error())
			return
		}
		models.Respond(conn, req.ID, manager.State())
	case "cycom.agentWorkspace.setUse":
		enabled, ok := models.Get[bool](req, "enabled")
		if !ok {
			models.RespondError(conn, req.ID, "enabled is required")
			return
		}
		if err := manager.SetUseAgentWorkspace(enabled); err != nil {
			models.RespondError(conn, req.ID, err.Error())
			return
		}
		models.Respond(conn, req.ID, manager.State())
	case "cycom.agentWorkspace.configure":
		widthValue, widthOK := requestNumber(req, "width")
		heightValue, heightOK := requestNumber(req, "height")
		refresh, refreshOK := requestNumber(req, "refresh")
		scale, scaleOK := requestNumber(req, "scale")
		if !widthOK || !heightOK || !refreshOK || !scaleOK {
			models.RespondError(conn, req.ID, "width, height, refresh, and scale are required")
			return
		}
		width := int(widthValue)
		height := int(heightValue)
		if float64(width) != widthValue || float64(height) != heightValue {
			models.RespondError(conn, req.ID, "width and height must be whole numbers")
			return
		}
		if err := manager.SetAgentWorkspaceDisplayConfig(width, height, refresh, scale); err != nil {
			models.RespondError(conn, req.ID, err.Error())
			return
		}
		models.Respond(conn, req.ID, manager.State())
	case "cycom.setPermission":
		scope, ok := models.Get[string](req, "scope")
		if !ok || strings.TrimSpace(scope) == "" {
			models.RespondError(conn, req.ID, "scope is required")
			return
		}
		enabled, ok := models.Get[bool](req, "enabled")
		if !ok {
			models.RespondError(conn, req.ID, "enabled is required")
			return
		}
		if err := manager.SetPermission(scope, enabled); err != nil {
			models.RespondError(conn, req.ID, err.Error())
			return
		}
		models.Respond(conn, req.ID, manager.State())
	case "cycom.approvals.list":
		models.Respond(conn, req.ID, manager.PendingApprovals())
	case "cycom.approvalMode.set":
		mode, ok := models.Get[string](req, "mode")
		if !ok || strings.TrimSpace(mode) == "" {
			models.RespondError(conn, req.ID, "mode is required")
			return
		}
		if err := manager.SetApprovalMode(mode); err != nil {
			models.RespondError(conn, req.ID, err.Error())
			return
		}
		models.Respond(conn, req.ID, manager.State())
	case "cycom.approval.respond":
		id, ok := models.Get[string](req, "id")
		if !ok || strings.TrimSpace(id) == "" {
			models.RespondError(conn, req.ID, "id is required")
			return
		}
		decision, ok := models.Get[string](req, "decision")
		if !ok || strings.TrimSpace(decision) == "" {
			models.RespondError(conn, req.ID, "decision is required")
			return
		}
		if err := manager.RespondApproval(id, decision); err != nil {
			models.RespondError(conn, req.ID, err.Error())
			return
		}
		models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "approval decision recorded"})
	case "cycom.appPolicies.list":
		models.Respond(conn, req.ID, manager.AppPolicies())
	case "cycom.appPolicy.set":
		appKey, ok := models.Get[string](req, "appKey")
		if !ok || strings.TrimSpace(appKey) == "" {
			models.RespondError(conn, req.ID, "appKey is required")
			return
		}
		appName, _ := models.Get[string](req, "appName")
		scope, ok := models.Get[string](req, "scope")
		if !ok || strings.TrimSpace(scope) == "" {
			models.RespondError(conn, req.ID, "scope is required")
			return
		}
		mode, ok := models.Get[string](req, "mode")
		if !ok {
			models.RespondError(conn, req.ID, "mode is required")
			return
		}
		if err := manager.SetAppPolicy(appKey, appName, scope, mode); err != nil {
			models.RespondError(conn, req.ID, err.Error())
			return
		}
		models.Respond(conn, req.ID, manager.State())
	case "cycom.appPolicy.clear":
		appKey, ok := models.Get[string](req, "appKey")
		if !ok || strings.TrimSpace(appKey) == "" {
			models.RespondError(conn, req.ID, "appKey is required")
			return
		}
		if err := manager.ClearAppPolicy(appKey); err != nil {
			models.RespondError(conn, req.ID, err.Error())
			return
		}
		models.Respond(conn, req.ID, manager.State())
	case "cycom.emergencyStop":
		if err := manager.EmergencyStop(); err != nil {
			models.RespondError(conn, req.ID, err.Error())
			return
		}
		models.Respond(conn, req.ID, manager.State())
	case "cycom.assistant.getState":
		if manager.assistant == nil {
			models.RespondError(conn, req.ID, "CyShell Assistant not initialized")
			return
		}
		models.Respond(conn, req.ID, manager.assistant.State())
	case "cycom.assistant.configure":
		if manager.assistant == nil {
			models.RespondError(conn, req.ID, "CyShell Assistant not initialized")
			return
		}
		endpoint, _ := models.Get[string](req, "endpoint")
		provider, _ := models.Get[string](req, "provider")
		model, _ := models.Get[string](req, "model")
		apiKey, _ := models.Get[string](req, "apiKey")
		clearKey, _ := models.Get[bool](req, "clearKey")
		state, err := manager.assistant.Configure(ctx, provider, endpoint, model, apiKey, clearKey)
		if err != nil {
			models.RespondError(conn, req.ID, err.Error())
			return
		}
		models.Respond(conn, req.ID, state)
	case "cycom.assistant.models":
		if manager.assistant == nil {
			models.RespondError(conn, req.ID, "CyShell Assistant not initialized")
			return
		}
		listCtx, done := manager.trackContext(ctx)
		defer done()
		availableModels, err := manager.assistant.ListModels(listCtx)
		if err != nil {
			models.RespondError(conn, req.ID, err.Error())
			return
		}
		models.Respond(conn, req.ID, availableModels)
	case "cycom.chat.history":
		if manager.assistant == nil {
			models.RespondError(conn, req.ID, "CyShell Assistant not initialized")
			return
		}
		models.Respond(conn, req.ID, manager.assistant.History())
	case "cycom.chat.clear":
		if manager.assistant == nil {
			models.RespondError(conn, req.ID, "CyShell Assistant not initialized")
			return
		}
		manager.assistant.Clear()
		models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "assistant history cleared"})
	case "cycom.chat":
		if manager.assistant == nil {
			models.RespondError(conn, req.ID, "CyShell Assistant not initialized")
			return
		}
		message, ok := models.Get[string](req, "message")
		if !ok || strings.TrimSpace(message) == "" {
			models.RespondError(conn, req.ID, "message is required")
			return
		}
		result, err := manager.assistant.Chat(ctx, message)
		if err != nil {
			models.RespondError(conn, req.ID, err.Error())
			return
		}
		models.Respond(conn, req.ID, result)
	default:
		models.RespondError(conn, req.ID, fmt.Sprintf("unknown CyCom method: %s", req.Method))
	}
}

func handleToolCall(ctx context.Context, conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	name, ok := models.Get[string](req, "name")
	if !ok || name == "" {
		models.RespondError(conn, req.ID, "name is required")
		return
	}
	reason, ok := models.Get[string](req, "reason")
	if !ok || reason == "" {
		models.RespondError(conn, req.ID, "reason is required")
		return
	}

	arguments, _ := models.Get[map[string]any](req, "arguments")
	if arguments == nil {
		arguments = map[string]any{}
	}
	arguments["reason"] = reason

	raw, err := json.Marshal(arguments)
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}
	origin := callOriginFromRequest(req)
	value, err := manager.CallWithOrigin(ctx, name, raw, origin)
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}
	models.Respond(conn, req.ID, value)
}

func (m *Manager) loadControl() error {
	m.enabled.Store(true)
	m.controlEnabled.Store(true)
	m.agentWorkspaceEnabled.Store(true)
	m.useAgentWorkspace.Store(true)
	m.workspaceMu.Lock()
	m.agentWorkspaceWidth = 1280
	m.agentWorkspaceHeight = 720
	m.agentWorkspaceRefresh = 60
	m.agentWorkspaceScale = 1
	m.workspaceMu.Unlock()
	if m.permissions == nil {
		m.permissions = defaultPermissionMap()
	}
	data, err := os.ReadFile(m.controlPath)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("read CyShell Agent control state: %w", err)
	}
	var cfg controlConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		return fmt.Errorf("decode CyShell Agent control state: %w", err)
	}
	m.enabled.Store(cfg.Enabled)
	m.controlEnabled.Store(cfg.ControlEnabled)
	if cfg.Version >= 5 {
		m.agentWorkspaceEnabled.Store(cfg.AgentWorkspaceEnabled)
		m.useAgentWorkspace.Store(cfg.UseAgentWorkspace)
	}
	if cfg.Version >= 6 {
		if width, height, refresh, scale, ok := normalizeAgentWorkspaceDisplayConfig(cfg.AgentWorkspaceWidth, cfg.AgentWorkspaceHeight, cfg.AgentWorkspaceRefresh, cfg.AgentWorkspaceScale); ok {
			m.workspaceMu.Lock()
			m.agentWorkspaceWidth = width
			m.agentWorkspaceHeight = height
			m.agentWorkspaceRefresh = refresh
			m.agentWorkspaceScale = scale
			m.workspaceMu.Unlock()
		}
	}
	if normalized, ok := normalizeApprovalMode(cfg.ApprovalMode); ok {
		m.approvalModeMu.Lock()
		m.approvalMode = normalized
		m.approvalModeMu.Unlock()
	}
	if len(cfg.Permissions) > 0 {
		m.permissionsMu.Lock()
		for _, spec := range permissionCatalog {
			if value, ok := cfg.Permissions[spec.ID]; ok {
				m.permissions[spec.ID] = value
			}
		}
		m.permissionsMu.Unlock()
	}
	if len(cfg.AppPolicies) > 0 {
		m.appPoliciesMu.Lock()
		for key, value := range cfg.AppPolicies {
			permissions := make(map[string]string)
			for scope, mode := range value.Permissions {
				if normalized, ok := normalizePolicyMode(mode); ok && normalized != "ask" && sensitiveAppScope(scope) {
					permissions[scope] = normalized
				}
			}
			if len(permissions) > 0 {
				m.appPolicies[key] = appPolicyConfig{Name: value.Name, Permissions: permissions}
			}
		}
		m.appPoliciesMu.Unlock()
	}
	return nil
}

func (m *Manager) persistControl() error {
	if err := os.MkdirAll(filepath.Dir(m.controlPath), 0o700); err != nil {
		return err
	}
	m.permissionsMu.RLock()
	permissions := make(map[string]bool, len(m.permissions))
	for id, enabled := range m.permissions {
		permissions[id] = enabled
	}
	m.permissionsMu.RUnlock()
	m.appPoliciesMu.RLock()
	appPolicies := make(map[string]appPolicyConfig, len(m.appPolicies))
	for key, cfg := range m.appPolicies {
		perms := make(map[string]string, len(cfg.Permissions))
		for scope, mode := range cfg.Permissions {
			perms[scope] = mode
		}
		appPolicies[key] = appPolicyConfig{Name: cfg.Name, Permissions: perms}
	}
	m.appPoliciesMu.RUnlock()
	workspaceWidth, workspaceHeight, workspaceRefresh, workspaceScale := m.AgentWorkspaceDisplayConfig()
	data, err := json.MarshalIndent(controlConfig{
		Version:               6,
		Enabled:               m.enabled.Load(),
		ControlEnabled:        m.controlEnabled.Load(),
		ApprovalMode:          m.ApprovalMode(),
		AgentWorkspaceEnabled: m.agentWorkspaceEnabled.Load(),
		UseAgentWorkspace:     m.useAgentWorkspace.Load(),
		AgentWorkspaceWidth:   workspaceWidth,
		AgentWorkspaceHeight:  workspaceHeight,
		AgentWorkspaceRefresh: workspaceRefresh,
		AgentWorkspaceScale:   workspaceScale,
		Permissions:           permissions,
		AppPolicies:           appPolicies,
	}, "", "  ")
	if err != nil {
		return err
	}
	tmp := m.controlPath + ".tmp"
	if err := os.WriteFile(tmp, append(data, '\n'), 0o600); err != nil {
		return err
	}
	if err := os.Chmod(tmp, 0o600); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, m.controlPath)
}

func (m *Manager) cancelActiveCalls() {
	m.activeMu.Lock()
	cancels := make([]context.CancelFunc, 0, len(m.activeCalls))
	for _, cancel := range m.activeCalls {
		cancels = append(cancels, cancel)
	}
	m.activeMu.Unlock()
	for _, cancel := range cancels {
		cancel()
	}
}

func (m *Manager) SetEnabled(enabled bool) error {
	m.enabled.Store(enabled)
	if !enabled {
		m.cancelActiveCalls()
	}
	err := m.persistControl()
	m.broadcastState()
	return err
}

func (m *Manager) SetControlEnabled(enabled bool) error {
	m.controlEnabled.Store(enabled)
	if !enabled {
		m.cancelActiveCalls()
	}
	err := m.persistControl()
	m.broadcastState()
	return err
}

func (m *Manager) EmergencyStop() error {
	m.controlEnabled.Store(false)
	m.cancelActiveCalls()
	err := m.persistControl()
	m.broadcastState()
	return err
}

func (m *Manager) toolReadOnly(name string) bool {
	for _, tool := range m.runtime.ListTools() {
		if tool.Name != name {
			continue
		}
		value, ok := tool.Annotations["readOnlyHint"].(bool)
		return ok && value
	}
	return false
}

func (m *Manager) trackContext(ctx context.Context) (context.Context, func()) {
	callCtx, cancel := context.WithCancel(ctx)
	id := m.callID.Add(1)
	m.activeMu.Lock()
	m.activeCalls[id] = cancel
	m.activeMu.Unlock()
	m.broadcastState()
	return callCtx, func() {
		cancel()
		m.activeMu.Lock()
		delete(m.activeCalls, id)
		m.activeMu.Unlock()
		m.broadcastState()
	}
}

func callOriginFromRequest(req ipc.Request) CallOrigin {
	origin := CallOrigin{Kind: "ipc", Name: "Local IPC client"}
	raw, ok := models.Get[map[string]any](req, "origin")
	if !ok || raw == nil {
		return origin
	}
	if value, ok := raw["kind"].(string); ok {
		origin.Kind = value
	}
	if value, ok := raw["name"].(string); ok {
		origin.Name = value
	}
	if value, ok := raw["version"].(string); ok {
		origin.Version = value
	}
	return normalizeCallOrigin(origin)
}

func (m *Manager) Call(ctx context.Context, name string, args json.RawMessage) (any, error) {
	return m.CallWithOrigin(ctx, name, args, CallOrigin{Kind: "internal", Name: "CyShell"})
}

func (m *Manager) CallWithOrigin(ctx context.Context, name string, args json.RawMessage, origin CallOrigin) (any, error) {
	callCtx, done := m.trackContext(ctx)
	activity := m.beginActivity(name, args, origin)
	value, err := m.runtime.Call(callCtx, name, args)
	done()
	m.finishActivity(activity, err, time.Now())
	return value, err
}
