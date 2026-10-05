package settingsstore

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"

	"github.com/Cytech-Team/CyShell-Desktop/core/internal/utils"
)

const (
	KindSettings = "settings"
	KindPlugins  = "plugins"
	KindSession  = "session"
)

type State struct {
	Revision uint64 `json:"revision"`
	Kind     string `json:"kind,omitempty"`
}

type Snapshot struct {
	Revision       uint64          `json:"revision"`
	Settings       json.RawMessage `json:"settings"`
	PluginSettings json.RawMessage `json:"pluginSettings"`
	Session        json.RawMessage `json:"session"`
}

type Manager struct {
	mu          sync.Mutex
	revision    uint64
	subscribers map[string]chan State
}

func NewManager() *Manager {
	return &Manager{
		revision:    1,
		subscribers: make(map[string]chan State),
	}
}

func (m *Manager) pathFor(kind string) (string, error) {
	base := filepath.Join(utils.XDGConfigHome(), "CyShell")
	switch kind {
	case "", KindSettings:
		return filepath.Join(base, "settings.json"), nil
	case KindPlugins:
		return filepath.Join(base, "plugin_settings.json"), nil
	case KindSession:
		return filepath.Join(utils.XDGStateHome(), "CyShell", "session.json"), nil
	default:
		return "", fmt.Errorf("unknown settings kind %q", kind)
	}
}

func readJSONFile(path string) json.RawMessage {
	data, err := os.ReadFile(path)
	if err != nil || len(data) == 0 || !json.Valid(data) {
		return json.RawMessage("{}")
	}
	return json.RawMessage(data)
}

func (m *Manager) Snapshot() Snapshot {
	m.mu.Lock()
	defer m.mu.Unlock()

	settingsPath, _ := m.pathFor(KindSettings)
	pluginsPath, _ := m.pathFor(KindPlugins)
	sessionPath, _ := m.pathFor(KindSession)
	return Snapshot{
		Revision:       m.revision,
		Settings:       readJSONFile(settingsPath),
		PluginSettings: readJSONFile(pluginsPath),
		Session:        readJSONFile(sessionPath),
	}
}

func (m *Manager) Replace(kind, raw string) (State, error) {
	path, err := m.pathFor(kind)
	if err != nil {
		return State{}, err
	}
	if !json.Valid([]byte(raw)) {
		return State{}, fmt.Errorf("invalid JSON")
	}

	var object map[string]any
	if err := json.Unmarshal([]byte(raw), &object); err != nil {
		return State{}, fmt.Errorf("settings payload must be a JSON object: %w", err)
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	if current, readErr := os.ReadFile(path); readErr == nil && string(current) == raw {
		return State{Revision: m.revision, Kind: normalizeKind(kind)}, nil
	}

	if err := writeAtomic(path, []byte(raw)); err != nil {
		return State{}, err
	}
	m.revision++
	state := State{Revision: m.revision, Kind: normalizeKind(kind)}
	m.broadcastLocked(state)
	return state, nil
}

func normalizeKind(kind string) string {
	if kind == "" {
		return KindSettings
	}
	return kind
}

func writeAtomic(path string, data []byte) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("create settings directory: %w", err)
	}

	tmp, err := os.CreateTemp(dir, ".cyshell-settings-*.tmp")
	if err != nil {
		return fmt.Errorf("create settings temp file: %w", err)
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath)

	if err := tmp.Chmod(0o644); err != nil {
		tmp.Close()
		return fmt.Errorf("chmod settings temp file: %w", err)
	}
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return fmt.Errorf("write settings temp file: %w", err)
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return fmt.Errorf("sync settings temp file: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("close settings temp file: %w", err)
	}
	if err := os.Rename(tmpPath, path); err != nil {
		return fmt.Errorf("replace settings file: %w", err)
	}
	return nil
}

func (m *Manager) Subscribe(id string) <-chan State {
	m.mu.Lock()
	defer m.mu.Unlock()

	if old, ok := m.subscribers[id]; ok {
		close(old)
	}
	ch := make(chan State, 8)
	m.subscribers[id] = ch
	return ch
}

func (m *Manager) Unsubscribe(id string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if ch, ok := m.subscribers[id]; ok {
		delete(m.subscribers, id)
		close(ch)
	}
}

func (m *Manager) GetState() State {
	m.mu.Lock()
	defer m.mu.Unlock()
	return State{Revision: m.revision}
}

func (m *Manager) broadcastLocked(state State) {
	for _, ch := range m.subscribers {
		select {
		case ch <- state:
		default:
		}
	}
}
