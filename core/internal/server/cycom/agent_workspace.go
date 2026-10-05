package cycom

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

const (
	agentWorkspaceService = "cycom-ai-desktop.service"
	agentWorkspaceOutput  = "HEADLESS-1"
)

func normalizeAgentWorkspaceDisplayConfig(width, height int, refresh, scale float64) (int, int, float64, float64, bool) {
	if width < 640 || width > 7680 || height < 480 || height > 4320 {
		return 0, 0, 0, 0, false
	}
	if refresh < 24 || refresh > 240 || scale < 0.5 || scale > 4 {
		return 0, 0, 0, 0, false
	}
	return width, height, refresh, scale, true
}

func (m *Manager) AgentWorkspaceDisplayConfig() (int, int, float64, float64) {
	m.workspaceMu.RLock()
	defer m.workspaceMu.RUnlock()
	return m.agentWorkspaceWidth, m.agentWorkspaceHeight, m.agentWorkspaceRefresh, m.agentWorkspaceScale
}

func agentWorkspaceEnvironment(display string) []string {
	runtimeDir := os.Getenv("XDG_RUNTIME_DIR")
	if runtimeDir == "" {
		runtimeDir = fmt.Sprintf("/run/user/%d", os.Getuid())
	}
	env := append([]string{}, os.Environ()...)
	env = append(env,
		"XDG_RUNTIME_DIR="+runtimeDir,
		"WAYLAND_DISPLAY="+display,
		"XDG_CURRENT_DESKTOP=labwc-ai",
		"XDG_SESSION_DESKTOP=labwc-ai",
	)
	return env
}

func (m *Manager) applyAgentWorkspaceDisplayConfig(requireActive bool) error {
	active, display := agentWorkspaceSocketState()
	if !active {
		if requireActive {
			return fmt.Errorf("Agent Workspace is not running")
		}
		return nil
	}
	binary, err := exec.LookPath("wlr-randr")
	if err != nil {
		return fmt.Errorf("Agent Workspace display control requires wlr-randr: %w", err)
	}
	width, height, refresh, scale := m.AgentWorkspaceDisplayConfig()
	mode := fmt.Sprintf("%dx%d@%.3fHz", width, height, refresh)
	cmd := exec.Command(binary,
		"--output", agentWorkspaceOutput,
		"--on",
		"--custom-mode", mode,
		"--pos", "0,0",
		"--scale", fmt.Sprintf("%.3f", scale),
	)
	cmd.Env = agentWorkspaceEnvironment(display)
	if output, err := cmd.CombinedOutput(); err != nil {
		message := strings.TrimSpace(string(output))
		if message == "" {
			message = err.Error()
		}
		return fmt.Errorf("apply Agent Workspace display config: %s", message)
	}
	return nil
}

func (m *Manager) SetAgentWorkspaceDisplayConfig(width, height int, refresh, scale float64) error {
	width, height, refresh, scale, ok := normalizeAgentWorkspaceDisplayConfig(width, height, refresh, scale)
	if !ok {
		return fmt.Errorf("invalid Agent Workspace display config; resolution 640x480..7680x4320, refresh 24..240 Hz, scale 0.5..4.0")
	}

	oldWidth, oldHeight, oldRefresh, oldScale := m.AgentWorkspaceDisplayConfig()
	m.workspaceMu.Lock()
	m.agentWorkspaceWidth = width
	m.agentWorkspaceHeight = height
	m.agentWorkspaceRefresh = refresh
	m.agentWorkspaceScale = scale
	m.workspaceMu.Unlock()

	if err := m.applyAgentWorkspaceDisplayConfig(false); err != nil {
		m.workspaceMu.Lock()
		m.agentWorkspaceWidth = oldWidth
		m.agentWorkspaceHeight = oldHeight
		m.agentWorkspaceRefresh = oldRefresh
		m.agentWorkspaceScale = oldScale
		m.workspaceMu.Unlock()
		_ = m.applyAgentWorkspaceDisplayConfig(false)
		return err
	}

	if err := m.persistControl(); err != nil {
		return err
	}
	m.broadcastState()
	return nil
}

func (m *Manager) applyAgentWorkspaceEnvironment() {
	if m.useAgentWorkspace.Load() {
		_ = os.Setenv("CYCOM_AGENT_WORKSPACE_AUTO", "1")
		return
	}
	_ = os.Setenv("CYCOM_AGENT_WORKSPACE_AUTO", "0")
}

func agentWorkspaceSocketState() (bool, string) {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return false, ""
	}
	statePath := filepath.Join(home, ".local", "state", "cycom-ai-desktop", "wayland-display")
	data, err := os.ReadFile(statePath)
	if err != nil {
		return false, ""
	}
	display := strings.TrimSpace(string(data))
	if display == "" {
		return false, ""
	}
	runtimeDir := os.Getenv("XDG_RUNTIME_DIR")
	if runtimeDir == "" {
		runtimeDir = fmt.Sprintf("/run/user/%d", os.Getuid())
	}
	st, err := os.Stat(filepath.Join(runtimeDir, display))
	if err != nil || st.Mode()&os.ModeSocket == 0 {
		return false, display
	}
	return true, display
}

func (m *Manager) AgentWorkspaceStatus() (bool, string) {
	return agentWorkspaceSocketState()
}

func (m *Manager) SetUseAgentWorkspace(enabled bool) error {
	m.useAgentWorkspace.Store(enabled)
	m.applyAgentWorkspaceEnvironment()
	// Routing changes apply to subsequent tool calls. Do not cancel calls that
	// are already running: the settings request itself may arrive through the
	// Agent/Desktop bridge and cancelling it would tear down the caller.
	if err := m.persistControl(); err != nil {
		return err
	}
	m.broadcastState()
	return nil
}

func (m *Manager) SetAgentWorkspaceEnabled(enabled bool) error {
	if runtime.GOOS != "linux" {
		return fmt.Errorf("Agent Workspace service control is only available on Linux")
	}

	action := "disable"
	args := []string{"--user", "disable", "--now", agentWorkspaceService}
	if enabled {
		action = "enable"
		args = []string{"--user", "enable", "--now", agentWorkspaceService}
	}

	cmd := exec.Command("systemctl", args...)
	if output, err := cmd.CombinedOutput(); err != nil {
		message := strings.TrimSpace(string(output))
		if message == "" {
			message = err.Error()
		}
		return fmt.Errorf("%s Agent Workspace: %s", action, message)
	}

	m.agentWorkspaceEnabled.Store(enabled)
	if !enabled {
		m.cancelActiveCalls()
	} else {
		// Give the isolated compositor a short chance to publish its Wayland
		// socket so the UI can immediately report Active after enabling it.
		for i := 0; i < 20; i++ {
			if active, _ := agentWorkspaceSocketState(); active {
				break
			}
			time.Sleep(100 * time.Millisecond)
		}
		if err := m.applyAgentWorkspaceDisplayConfig(true); err != nil {
			_ = m.persistControl()
			m.broadcastState()
			return err
		}
	}

	if err := m.persistControl(); err != nil {
		return err
	}
	m.broadcastState()
	return nil
}
