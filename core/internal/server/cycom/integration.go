package cycom

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const (
	integrationModeLocal  = "local"
	integrationModeTunnel = "chatgpt-tunnel"
	integrationModeAPI    = "api"
)

type IntegrationConfig struct {
	Version          int    `json:"version"`
	Mode             string `json:"mode"`
	ExternalFallback bool   `json:"externalFallback"`
	AgentAppEnabled  bool   `json:"agentAppEnabled"`
}

type IntegrationState struct {
	Mode                  string             `json:"mode"`
	ExternalFallback      bool               `json:"externalFallback"`
	AgentAppEnabled       bool               `json:"agentAppEnabled"`
	AgentClients          []AgentClientState `json:"agentClients"`
	CompanionInstalled    bool               `json:"companionInstalled"`
	TunnelClientInstalled bool               `json:"tunnelClientInstalled"`
	TunnelConfigured      bool               `json:"tunnelConfigured"`
	BridgeInstalled       bool               `json:"bridgeInstalled"`
	BridgeActive          bool               `json:"bridgeActive"`
	CompanionActive       bool               `json:"companionActive"`
	TunnelActive          bool               `json:"tunnelActive"`
	APIURL                string             `json:"apiUrl"`
	AgentAppConfigPath    string             `json:"agentAppConfigPath"`
	IntegrationConfigPath string             `json:"integrationConfigPath"`
	TunnelCredentialsPath string             `json:"tunnelCredentialsPath"`
	LastError             string             `json:"lastError,omitempty"`
}

type AgentClientState struct {
	ID            string `json:"id"`
	Installed     bool   `json:"installed"`
	Supported     bool   `json:"supported"`
	Connected     bool   `json:"connected"`
	CanConnect    bool   `json:"canConnect"`
	CanDisconnect bool   `json:"canDisconnect"`
	ConfigPath    string `json:"configPath,omitempty"`
	Reason        string `json:"reason,omitempty"`
}

const (
	agentClientCodex    = "codex"
	agentClientOpenCode = "opencode"
	agentClientVSCode   = "vscode"

	codexServerID    = "cyshell-desktop-codex"
	openCodeServerID = "cyshell-desktop-opencode"
	vsCodeServerID   = "cyshell-desktop-vscode"
)

func defaultAgentConfigDir() string {
	if xdg := strings.TrimSpace(os.Getenv("XDG_CONFIG_HOME")); xdg != "" {
		return filepath.Join(xdg, "cycomagent")
	}
	if home, err := os.UserHomeDir(); err == nil {
		return filepath.Join(home, ".config", "cycomagent")
	}
	return filepath.Join(".", ".cycomagent-config")
}

func defaultIntegrationConfig() IntegrationConfig {
	return IntegrationConfig{Version: 1, Mode: integrationModeLocal, ExternalFallback: false}
}

func normalizeIntegrationMode(mode string) (string, error) {
	switch strings.TrimSpace(strings.ToLower(mode)) {
	case "", integrationModeLocal:
		return integrationModeLocal, nil
	case integrationModeTunnel, "tunnel", "chatgpt":
		return integrationModeTunnel, nil
	case integrationModeAPI, "http":
		return integrationModeAPI, nil
	default:
		return "", fmt.Errorf("unsupported Agent connection mode %q", mode)
	}
}

func (m *Manager) integrationConfigPath() string {
	return filepath.Join(defaultAgentConfigDir(), "cyshell-integration.json")
}

func (m *Manager) tunnelCredentialsPath() string {
	name := strings.TrimSpace(os.Getenv("USER"))
	if name == "" {
		if current, err := user.Current(); err == nil {
			name = current.Username
		}
	}
	if name == "" {
		name = "user"
	}
	return filepath.Join(defaultAgentConfigDir(), name+"-tunnel.env")
}

func (m *Manager) agentAppConfigPath() string {
	return filepath.Join(defaultAgentConfigDir(), "clients", "agent-app.json")
}

func homePath(parts ...string) string {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return filepath.Join(append([]string{"."}, parts...)...)
	}
	return filepath.Join(append([]string{home}, parts...)...)
}

func codexConfigPath() string {
	if root := strings.TrimSpace(os.Getenv("CODEX_HOME")); root != "" {
		return filepath.Join(root, "config.toml")
	}
	return homePath(".codex", "config.toml")
}

func openCodeConfigPaths() (string, string) {
	configHome := strings.TrimSpace(os.Getenv("XDG_CONFIG_HOME"))
	if configHome == "" {
		configHome = homePath(".config")
	}
	dir := filepath.Join(configHome, "opencode")
	return filepath.Join(dir, "opencode.json"), filepath.Join(dir, "opencode.jsonc")
}

func vsCodeUserConfigDir(codePath string) (string, string) {
	if strings.TrimSpace(os.Getenv("VSCODE_PORTABLE")) != "" {
		return "", "profile_override"
	}
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return "", "config_unavailable"
	}
	defaultDir := filepath.Join(home, ".config", "Code", "User")
	snapDir := filepath.Join(home, "snap", "code", "current", ".config", "Code", "User")
	flatpakDir := filepath.Join(home, ".var", "app", "com.visualstudio.code", "config", "Code", "User")
	var existing []string
	for _, dir := range []string{defaultDir, snapDir, flatpakDir} {
		if info, statErr := os.Stat(dir); statErr == nil && info.IsDir() {
			existing = append(existing, dir)
		}
	}
	if len(existing) > 1 {
		return "", "multiple_user_configs"
	}
	var userDir string
	if len(existing) == 1 {
		userDir = existing[0]
	} else if strings.Contains(codePath, "/snap/") || strings.HasPrefix(codePath, "/snap/") {
		userDir = snapDir
	} else if strings.Contains(codePath, "flatpak") {
		userDir = flatpakDir
	} else {
		userDir = defaultDir
	}
	profiles, _ := filepath.Glob(filepath.Join(userDir, "profiles", "*"))
	for _, profile := range profiles {
		if info, statErr := os.Stat(profile); statErr == nil && info.IsDir() {
			return userDir, "profile_selection_unknown"
		}
	}
	return userDir, ""
}

func (m *Manager) systemdUserDir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "systemd", "user")
}

func (m *Manager) loadIntegrationConfig() IntegrationConfig {
	cfg := defaultIntegrationConfig()
	data, err := os.ReadFile(m.integrationConfigPath())
	if err != nil {
		if userServiceActive("cycomagent-tunnel.service") {
			cfg.Mode = integrationModeTunnel
		} else if userServiceActive("cyshell-mcp-http.service") {
			cfg.Mode = integrationModeAPI
		}
		if _, statErr := os.Stat(m.agentAppConfigPath()); statErr == nil {
			cfg.AgentAppEnabled = true
		}
		return cfg
	}
	if json.Unmarshal(data, &cfg) != nil {
		return defaultIntegrationConfig()
	}
	mode, err := normalizeIntegrationMode(cfg.Mode)
	if err != nil {
		cfg.Mode = integrationModeLocal
	} else {
		cfg.Mode = mode
	}
	if cfg.Version == 0 {
		cfg.Version = 1
	}
	return cfg
}

func writeJSONAtomic(path string, value any, mode os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, mode); err != nil {
		return err
	}
	if err := os.Chmod(tmp, mode); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, path)
}

func (m *Manager) persistIntegrationConfig(cfg IntegrationConfig) error {
	cfg.Version = 1
	return writeJSONAtomic(m.integrationConfigPath(), cfg, 0o600)
}

func executable(name string) string {
	path, err := exec.LookPath(name)
	if err != nil {
		return ""
	}
	absolute, err := filepath.Abs(path)
	if err == nil {
		return absolute
	}
	return path
}

func userServiceActive(name string) bool {
	return exec.Command("systemctl", "--user", "is-active", "--quiet", name).Run() == nil
}

func envHasTunnelCredentials(path string) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	var hasID, hasKey bool
	for _, raw := range strings.Split(string(data), "\n") {
		line := strings.TrimSpace(raw)
		switch {
		case strings.HasPrefix(line, "CONTROL_PLANE_TUNNEL_ID="):
			hasID = strings.TrimSpace(strings.TrimPrefix(line, "CONTROL_PLANE_TUNNEL_ID=")) != ""
		case strings.HasPrefix(line, "CONTROL_PLANE_API_KEY="):
			hasKey = strings.TrimSpace(strings.TrimPrefix(line, "CONTROL_PLANE_API_KEY=")) != ""
		}
	}
	return hasID && hasKey
}

func (m *Manager) IntegrationState() IntegrationState {
	cfg := m.loadIntegrationConfig()
	return IntegrationState{
		Mode:                  cfg.Mode,
		ExternalFallback:      cfg.ExternalFallback,
		AgentAppEnabled:       cfg.AgentAppEnabled,
		AgentClients:          m.agentClientStates(),
		CompanionInstalled:    executable("cycomagent") != "",
		TunnelClientInstalled: executable("tunnel-client") != "",
		BridgeInstalled:       executable("cyshell-mcp") != "",
		TunnelConfigured:      envHasTunnelCredentials(m.tunnelCredentialsPath()),
		BridgeActive:          userServiceActive("cyshell-mcp-http.service"),
		CompanionActive:       userServiceActive("cycomagent-fallback.service") || (cfg.ExternalFallback && externalFallbackEndpointReady()),
		TunnelActive:          userServiceActive("cycomagent-tunnel.service"),
		APIURL:                "http://127.0.0.1:7333/mcp",
		AgentAppConfigPath:    m.agentAppConfigPath(),
		IntegrationConfigPath: m.integrationConfigPath(),
		TunnelCredentialsPath: m.tunnelCredentialsPath(),
	}
}

type jsoncProperty struct {
	key      string
	keyStart int
	value    *jsoncNode
	comma    int
}

type jsoncNode struct {
	kind       byte
	start      int
	end        int
	close      int
	properties []jsoncProperty
}

type jsoncParser struct {
	data []byte
	pos  int
}

func (p *jsoncParser) skipTrivia() error {
	for p.pos < len(p.data) {
		if p.data[p.pos] == ' ' || p.data[p.pos] == '\t' || p.data[p.pos] == '\r' || p.data[p.pos] == '\n' {
			p.pos++
			continue
		}
		if p.pos+1 >= len(p.data) || p.data[p.pos] != '/' {
			return nil
		}
		switch p.data[p.pos+1] {
		case '/':
			p.pos += 2
			for p.pos < len(p.data) && p.data[p.pos] != '\n' {
				p.pos++
			}
		case '*':
			p.pos += 2
			closed := false
			for p.pos+1 < len(p.data) {
				if p.data[p.pos] == '*' && p.data[p.pos+1] == '/' {
					p.pos += 2
					closed = true
					break
				}
				p.pos++
			}
			if !closed {
				return errors.New("unterminated JSONC comment")
			}
		default:
			return nil
		}
	}
	return nil
}

func (p *jsoncParser) parseString() (string, error) {
	if p.pos >= len(p.data) || p.data[p.pos] != '"' {
		return "", errors.New("expected JSON string")
	}
	start := p.pos
	p.pos++
	escaped := false
	for p.pos < len(p.data) {
		c := p.data[p.pos]
		p.pos++
		if escaped {
			escaped = false
			continue
		}
		if c == '\\' {
			escaped = true
			continue
		}
		if c == '"' {
			var value string
			if err := json.Unmarshal(p.data[start:p.pos], &value); err != nil {
				return "", err
			}
			return value, nil
		}
	}
	return "", errors.New("unterminated JSON string")
}

func (p *jsoncParser) parseValue() (*jsoncNode, error) {
	if err := p.skipTrivia(); err != nil {
		return nil, err
	}
	if p.pos >= len(p.data) {
		return nil, errors.New("missing JSON value")
	}
	start := p.pos
	switch p.data[p.pos] {
	case '{':
		p.pos++
		node := &jsoncNode{kind: '{', start: start}
		if err := p.skipTrivia(); err != nil {
			return nil, err
		}
		if p.pos < len(p.data) && p.data[p.pos] == '}' {
			node.close = p.pos
			p.pos++
			node.end = p.pos
			return node, nil
		}
		for {
			if err := p.skipTrivia(); err != nil {
				return nil, err
			}
			keyStart := p.pos
			key, err := p.parseString()
			if err != nil {
				return nil, err
			}
			if err := p.skipTrivia(); err != nil {
				return nil, err
			}
			if p.pos >= len(p.data) || p.data[p.pos] != ':' {
				return nil, errors.New("expected colon after JSON property")
			}
			p.pos++
			value, err := p.parseValue()
			if err != nil {
				return nil, err
			}
			if err := p.skipTrivia(); err != nil {
				return nil, err
			}
			comma := -1
			if p.pos < len(p.data) && p.data[p.pos] == ',' {
				comma = p.pos
				p.pos++
			}
			node.properties = append(node.properties, jsoncProperty{key: key, keyStart: keyStart, value: value, comma: comma})
			if err := p.skipTrivia(); err != nil {
				return nil, err
			}
			if p.pos >= len(p.data) {
				return nil, errors.New("unterminated JSON object")
			}
			if p.data[p.pos] == '}' {
				node.close = p.pos
				p.pos++
				node.end = p.pos
				return node, nil
			}
			if comma < 0 {
				return nil, errors.New("expected comma between JSON properties")
			}
		}
	case '[':
		p.pos++
		for {
			if err := p.skipTrivia(); err != nil {
				return nil, err
			}
			if p.pos < len(p.data) && p.data[p.pos] == ']' {
				p.pos++
				return &jsoncNode{kind: '[', start: start, end: p.pos, close: p.pos - 1}, nil
			}
			if p.pos >= len(p.data) {
				return nil, errors.New("unterminated JSON array")
			}
			if _, err := p.parseValue(); err != nil {
				return nil, err
			}
			if err := p.skipTrivia(); err != nil {
				return nil, err
			}
			if p.pos < len(p.data) && p.data[p.pos] == ',' {
				p.pos++
				continue
			}
			if p.pos < len(p.data) && p.data[p.pos] == ']' {
				p.pos++
				return &jsoncNode{kind: '[', start: start, end: p.pos, close: p.pos - 1}, nil
			}
			return nil, errors.New("expected comma between JSON array values")
		}
	case '"':
		if _, err := p.parseString(); err != nil {
			return nil, err
		}
		return &jsoncNode{kind: '"', start: start, end: p.pos}, nil
	default:
		for p.pos < len(p.data) {
			c := p.data[p.pos]
			if c == ',' || c == '}' || c == ']' || c == ' ' || c == '\t' || c == '\r' || c == '\n' {
				break
			}
			if c == '/' && p.pos+1 < len(p.data) && (p.data[p.pos+1] == '/' || p.data[p.pos+1] == '*') {
				break
			}
			p.pos++
		}
		if p.pos == start {
			return nil, errors.New("invalid JSON value")
		}
		return &jsoncNode{kind: 'v', start: start, end: p.pos}, nil
	}
}

func parseJSONC(data []byte) (*jsoncNode, error) {
	p := &jsoncParser{data: data}
	root, err := p.parseValue()
	if err != nil {
		return nil, err
	}
	if err := p.skipTrivia(); err != nil {
		return nil, err
	}
	if p.pos != len(data) {
		return nil, errors.New("unexpected data after JSON value")
	}
	if root.kind != '{' {
		return nil, errors.New("configuration root must be an object")
	}
	cleaned, err := stripJSONC(data)
	if err != nil {
		return nil, err
	}
	if !json.Valid(cleaned) {
		return nil, errors.New("invalid JSONC configuration")
	}
	return root, nil
}

func stripJSONC(data []byte) ([]byte, error) {
	cleaned := make([]byte, 0, len(data))
	inString := false
	escaped := false
	for i := 0; i < len(data); i++ {
		c := data[i]
		if inString {
			cleaned = append(cleaned, c)
			if escaped {
				escaped = false
			} else if c == '\\' {
				escaped = true
			} else if c == '"' {
				inString = false
			}
			continue
		}
		if c == '"' {
			inString = true
			cleaned = append(cleaned, c)
			continue
		}
		if c != '/' || i+1 >= len(data) {
			cleaned = append(cleaned, c)
			continue
		}
		switch data[i+1] {
		case '/':
			i += 2
			for i < len(data) && data[i] != '\n' {
				i++
			}
			if i < len(data) {
				cleaned = append(cleaned, '\n')
			}
		case '*':
			i += 2
			closed := false
			for i+1 < len(data) {
				if data[i] == '*' && data[i+1] == '/' {
					i++
					closed = true
					break
				}
				if data[i] == '\n' {
					cleaned = append(cleaned, '\n')
				}
				i++
			}
			if !closed {
				return nil, errors.New("unterminated JSONC comment")
			}
		default:
			cleaned = append(cleaned, c)
		}
	}
	if inString {
		return nil, errors.New("unterminated JSON string")
	}
	result := make([]byte, 0, len(cleaned))
	inString = false
	escaped = false
	for i := 0; i < len(cleaned); i++ {
		c := cleaned[i]
		if inString {
			result = append(result, c)
			if escaped {
				escaped = false
			} else if c == '\\' {
				escaped = true
			} else if c == '"' {
				inString = false
			}
			continue
		}
		if c == '"' {
			inString = true
			result = append(result, c)
			continue
		}
		if c == ',' {
			j := i + 1
			for j < len(cleaned) && (cleaned[j] == ' ' || cleaned[j] == '\t' || cleaned[j] == '\r' || cleaned[j] == '\n') {
				j++
			}
			if j < len(cleaned) && (cleaned[j] == '}' || cleaned[j] == ']') {
				continue
			}
		}
		result = append(result, c)
	}
	return result, nil
}

func decodeJSONCNode(data []byte, node *jsoncNode, target any) error {
	cleaned, err := stripJSONC(data[node.start:node.end])
	if err != nil {
		return err
	}
	decoder := json.NewDecoder(bytes.NewReader(cleaned))
	decoder.UseNumber()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	if err := decoder.Decode(new(any)); !errors.Is(err, io.EOF) {
		return errors.New("unexpected data in JSON value")
	}
	return nil
}

func jsoncPropertyAt(node *jsoncNode, name string) (int, *jsoncNode) {
	if node == nil || node.kind != '{' {
		return -1, nil
	}
	for index, property := range node.properties {
		if property.key == name {
			return index, property.value
		}
	}
	return -1, nil
}

func jsoncPropertyCount(node *jsoncNode, name string) int {
	if node == nil || node.kind != '{' {
		return 0
	}
	count := 0
	for _, property := range node.properties {
		if property.key == name {
			count++
		}
	}
	return count
}

func lineIndent(data []byte, offset int) string {
	if offset > len(data) {
		offset = len(data)
	}
	lineStart := bytes.LastIndexByte(data[:offset], '\n') + 1
	indent := string(data[lineStart:offset])
	for _, r := range indent {
		if r != ' ' && r != '\t' {
			return ""
		}
	}
	return indent
}

func jsoncChildIndent(data []byte, object *jsoncNode) (string, string) {
	closeIndent := lineIndent(data, object.close)
	if len(object.properties) > 0 {
		return lineIndent(data, object.properties[0].keyStart), closeIndent
	}
	step := "  "
	if strings.Contains(closeIndent, "\t") {
		step = "\t"
	}
	return closeIndent + step, closeIndent
}

func insertJSONCProperty(data []byte, object *jsoncNode, key, value string) ([]byte, error) {
	if object == nil || object.kind != '{' {
		return nil, errors.New("JSON value is not an object")
	}
	if _, existing := jsoncPropertyAt(object, key); existing != nil {
		return nil, fmt.Errorf("JSON property %q already exists", key)
	}
	quotedKey, _ := json.Marshal(key)
	propertyIndent, closeIndent := jsoncChildIndent(data, object)
	insert := []byte("\n" + propertyIndent + string(quotedKey) + ": " + value + "\n" + closeIndent)
	position := object.close
	if len(object.properties) > 0 {
		last := object.properties[len(object.properties)-1]
		if last.comma >= 0 {
			position = last.comma + 1
			insert = []byte("\n" + propertyIndent + string(quotedKey) + ": " + value)
		} else {
			position = last.value.end
			insert = []byte(",\n" + propertyIndent + string(quotedKey) + ": " + value)
		}
	}
	result := make([]byte, 0, len(data)+len(insert))
	result = append(result, data[:position]...)
	result = append(result, insert...)
	result = append(result, data[position:]...)
	return result, nil
}

func removeJSONCProperty(data []byte, object *jsoncNode, index int) ([]byte, error) {
	if object == nil || object.kind != '{' || index < 0 || index >= len(object.properties) {
		return nil, errors.New("JSON property is unavailable")
	}
	property := object.properties[index]
	start, end := property.keyStart, property.value.end
	if index < len(object.properties)-1 {
		if property.comma < 0 {
			return nil, errors.New("JSON property separator is unavailable")
		}
		end = property.comma + 1
	} else if index > 0 {
		separator := object.properties[index-1].comma
		if separator < 0 {
			return nil, errors.New("JSON property separator is unavailable")
		}
		start = separator
		if property.comma >= 0 {
			end = property.comma + 1
		}
	} else if property.comma >= 0 {
		end = property.comma + 1
	}
	if start > end || end > len(data) {
		return nil, errors.New("JSON property range is invalid")
	}
	result := make([]byte, 0, len(data)-(end-start))
	result = append(result, data[:start]...)
	result = append(result, data[end:]...)
	return result, nil
}

func readJSONCConfig(path string) ([]byte, os.FileMode, bool, error) {
	info, err := os.Lstat(path)
	if os.IsNotExist(err) {
		return []byte("{}\n"), 0o600, false, nil
	}
	if err != nil {
		return nil, 0, false, err
	}
	if !info.Mode().IsRegular() {
		return nil, 0, true, errors.New("configuration is not a regular file")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, 0, true, err
	}
	if _, err := parseJSONC(data); err != nil {
		return nil, 0, true, err
	}
	return data, info.Mode().Perm(), true, nil
}

func writeClientConfigAtomic(path string, data []byte, mode os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	if mode == 0 {
		mode = 0o600
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".cyshell-mcp-*")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath)
	if err := tmp.Chmod(mode); err != nil {
		_ = tmp.Close()
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmpPath, path)
}

func jsoncEntryMatches(data []byte, node *jsoncNode, clientID string, mcpPath string) bool {
	var entry map[string]any
	if node == nil || node.kind != '{' || decodeJSONCNode(data, node, &entry) != nil {
		return false
	}
	seen := make(map[string]struct{}, len(node.properties))
	for _, property := range node.properties {
		if _, exists := seen[property.key]; exists {
			return false
		}
		seen[property.key] = struct{}{}
	}
	if clientID == agentClientOpenCode {
		if len(entry) != 2 || entry["type"] != "local" {
			return false
		}
		command, ok := entry["command"].([]any)
		if !ok || len(command) != 1 {
			return false
		}
		value, ok := command[0].(string)
		return ok && isCyShellMCPCommand(value, mcpPath)
	}
	if clientID == agentClientVSCode {
		if len(entry) != 1 {
			return false
		}
		command, ok := entry["command"].(string)
		return ok && isCyShellMCPCommand(command, mcpPath)
	}
	return false
}

func isCyShellMCPCommand(command string, currentPath string) bool {
	return currentPath != "" && filepath.Clean(command) == filepath.Clean(currentPath)
}

func nestedClientEntryJSON(keys []string, start int, serverID string, entryJSON string) string {
	quotedID, _ := json.Marshal(serverID)
	value := "{" + string(quotedID) + ":" + entryJSON + "}"
	for index := len(keys) - 1; index > start; index-- {
		quotedKey, _ := json.Marshal(keys[index])
		value = "{" + string(quotedKey) + ":" + value + "}"
	}
	return value
}

func modifyJSONCClientConfig(path string, wrapperKeys []string, serverID string, entry map[string]any, clientID string, mcpPath string, connect bool) error {
	data, mode, exists, err := readJSONCConfig(path)
	if err != nil {
		return fmt.Errorf("cannot safely read client config: %w", err)
	}
	if !exists && !connect {
		return nil
	}
	root, err := parseJSONC(data)
	if err != nil {
		return fmt.Errorf("cannot safely parse client config: %w", err)
	}
	entryJSONBytes, err := json.Marshal(entry)
	if err != nil {
		return err
	}
	entryJSON := string(entryJSONBytes)
	current := root
	for index, key := range wrapperKeys {
		if jsoncPropertyCount(current, key) > 1 {
			return fmt.Errorf("client config field %q is ambiguous", key)
		}
		propertyIndex, child := jsoncPropertyAt(current, key)
		if propertyIndex < 0 {
			if !connect {
				return nil
			}
			value := nestedClientEntryJSON(wrapperKeys, index, serverID, entryJSON)
			updated, err := insertJSONCProperty(data, current, key, value)
			if err != nil {
				return err
			}
			if _, err := parseJSONC(updated); err != nil {
				return fmt.Errorf("cannot safely update client config: %w", err)
			}
			return writeClientConfigAtomic(path, updated, mode)
		}
		if child.kind != '{' {
			return fmt.Errorf("client config field %q is not an object", key)
		}
		current = child
	}
	if jsoncPropertyCount(current, serverID) > 1 {
		return fmt.Errorf("reserved CyShell server ID %q is ambiguous", serverID)
	}
	propertyIndex, server := jsoncPropertyAt(current, serverID)
	if propertyIndex < 0 {
		if !connect {
			return nil
		}
		updated, err := insertJSONCProperty(data, current, serverID, entryJSON)
		if err != nil {
			return err
		}
		if _, err := parseJSONC(updated); err != nil {
			return fmt.Errorf("cannot safely update client config: %w", err)
		}
		return writeClientConfigAtomic(path, updated, mode)
	}
	if !jsoncEntryMatches(data, server, clientID, mcpPath) {
		return fmt.Errorf("reserved CyShell server ID %q belongs to a different config", serverID)
	}
	if connect {
		return nil
	}
	updated, err := removeJSONCProperty(data, current, propertyIndex)
	if err != nil {
		return err
	}
	if _, err := parseJSONC(updated); err != nil {
		return fmt.Errorf("cannot safely update client config: %w", err)
	}
	return writeClientConfigAtomic(path, updated, mode)
}

func inspectJSONCClientConfig(path string, wrapperKeys []string, serverID string, clientID string, mcpPath string) (bool, string) {
	data, _, exists, err := readJSONCConfig(path)
	if err != nil {
		return false, "config_invalid"
	}
	if !exists {
		return false, ""
	}
	root, err := parseJSONC(data)
	if err != nil {
		return false, "config_invalid"
	}
	current := root
	for _, key := range wrapperKeys {
		if jsoncPropertyCount(current, key) > 1 {
			return false, "config_invalid"
		}
		_, child := jsoncPropertyAt(current, key)
		if child == nil {
			return false, ""
		}
		if child.kind != '{' {
			return false, "config_invalid"
		}
		current = child
	}
	if jsoncPropertyCount(current, serverID) > 1 {
		return false, "config_conflict"
	}
	_, server := jsoncPropertyAt(current, serverID)
	if server == nil {
		return false, ""
	}
	if mcpPath == "" {
		return false, "server_missing"
	}
	if !jsoncEntryMatches(data, server, clientID, mcpPath) {
		return false, "config_conflict"
	}
	return true, ""
}

func openCodeConfigPath() (string, string) {
	jsonPath, jsoncPath := openCodeConfigPaths()
	_, jsonErr := os.Lstat(jsonPath)
	_, jsoncErr := os.Lstat(jsoncPath)
	if jsonErr != nil && !os.IsNotExist(jsonErr) {
		return jsonPath, "config_invalid"
	}
	if jsoncErr != nil && !os.IsNotExist(jsoncErr) {
		return jsoncPath, "config_invalid"
	}
	jsonExists := jsonErr == nil
	jsoncExists := jsoncErr == nil
	if jsonExists && jsoncExists {
		return jsonPath, "multiple_configs"
	}
	if jsoncExists {
		return jsoncPath, ""
	}
	return jsonPath, ""
}

func (m *Manager) openCodeClientState(mcpPath string) AgentClientState {
	clientPath := executable("opencode")
	state := AgentClientState{ID: agentClientOpenCode, Installed: clientPath != "", Supported: true}
	if !state.Installed {
		return state
	}
	state.ConfigPath, state.Reason = openCodeConfigPath()
	if override := strings.TrimSpace(os.Getenv("OPENCODE_CONFIG")); override != "" && state.Reason == "" {
		state.Reason = "config_override"
	}
	if override := strings.TrimSpace(os.Getenv("OPENCODE_CONFIG_DIR")); override != "" && state.Reason == "" {
		state.Reason = "config_override"
	}
	if state.Reason != "" {
		state.Supported = false
		return state
	}
	state.Connected, state.Reason = inspectJSONCClientConfig(state.ConfigPath, []string{"mcp", "servers"}, openCodeServerID, agentClientOpenCode, mcpPath)
	if state.Reason != "" {
		state.Supported = false
		return state
	}
	if mcpPath == "" {
		state.Reason = "server_missing"
	}
	state.CanConnect = !state.Connected && mcpPath != ""
	state.CanDisconnect = state.Connected && mcpPath != ""
	return state
}

func (m *Manager) vsCodeClientState(mcpPath string) AgentClientState {
	clientPath := executable("code")
	state := AgentClientState{ID: agentClientVSCode, Installed: clientPath != "", Supported: true}
	if !state.Installed {
		return state
	}
	userDir, reason := vsCodeUserConfigDir(clientPath)
	if userDir == "" {
		state.Reason = reason
		state.Supported = false
		return state
	}
	state.ConfigPath = filepath.Join(userDir, "mcp.json")
	if reason != "" {
		state.Reason = reason
		state.Supported = false
		return state
	}
	state.Connected, state.Reason = inspectJSONCClientConfig(state.ConfigPath, []string{"servers"}, vsCodeServerID, agentClientVSCode, mcpPath)
	if state.Reason != "" {
		state.Supported = false
		return state
	}
	if mcpPath == "" {
		state.Reason = "server_missing"
	}
	state.CanConnect = !state.Connected && mcpPath != ""
	state.CanDisconnect = state.Connected && mcpPath != ""
	return state
}

func (m *Manager) agentClientStates() []AgentClientState {
	mcpPath := executable("cyshell-mcp")
	return []AgentClientState{
		m.codexClientState(mcpPath),
		m.openCodeClientState(mcpPath),
		m.vsCodeClientState(mcpPath),
	}
}

func (m *Manager) codexClientState(mcpPath string) AgentClientState {
	clientPath := executable("codex")
	configPath := codexConfigPath()
	if absolute, err := filepath.Abs(configPath); err == nil {
		configPath = absolute
	}
	state := AgentClientState{ID: agentClientCodex, Installed: clientPath != "", Supported: true, ConfigPath: configPath}
	if !state.Installed {
		return state
	}
	data, err := os.ReadFile(configPath)
	if err != nil && !os.IsNotExist(err) {
		state.Supported = false
		state.Reason = "config_invalid"
		return state
	}
	if err == nil {
		state.Connected, state.Reason = inspectCodexServer(data, codexServerID, mcpPath)
		if state.Reason != "" {
			state.Supported = false
			return state
		}
	}
	if mcpPath == "" {
		state.Reason = "server_missing"
	}
	state.CanConnect = !state.Connected && mcpPath != ""
	state.CanDisconnect = state.Connected && mcpPath != ""
	return state
}

func (m *Manager) SetAgentClientConnected(clientID string, connected bool) (IntegrationState, error) {
	m.integrationClientMu.Lock()
	defer m.integrationClientMu.Unlock()

	var state AgentClientState
	for _, candidate := range m.agentClientStates() {
		if candidate.ID == clientID {
			state = candidate
			break
		}
	}
	if state.ID == "" {
		return IntegrationState{}, fmt.Errorf("unsupported Agent client %q", clientID)
	}
	if !state.Installed {
		return IntegrationState{}, errors.New("Agent client is not installed")
	}
	if !state.Supported {
		return IntegrationState{}, fmt.Errorf("Agent client config is unavailable: %s", state.Reason)
	}
	if connected == state.Connected {
		return m.IntegrationState(), nil
	}
	if connected && !state.CanConnect {
		return IntegrationState{}, errors.New("CyShell MCP executable is not installed")
	}
	if !connected && !state.CanDisconnect {
		return m.IntegrationState(), nil
	}

	mcpPath := executable("cyshell-mcp")
	switch clientID {
	case agentClientCodex:
		codexPath := executable("codex")
		if connected {
			if err := runCodexMCPCommandError(codexPath, "add", codexServerID, mcpPath); err != nil {
				return IntegrationState{}, err
			}
		} else if err := runCodexMCPCommandError(codexPath, "remove", codexServerID); err != nil {
			return IntegrationState{}, err
		}
	case agentClientOpenCode:
		path, reason := openCodeConfigPath()
		if reason != "" {
			return IntegrationState{}, fmt.Errorf("OpenCode config is unavailable: %s", reason)
		}
		entry := map[string]any{"type": "local", "command": []string{mcpPath}}
		if err := modifyJSONCClientConfig(path, []string{"mcp", "servers"}, openCodeServerID, entry, agentClientOpenCode, mcpPath, connected); err != nil {
			return IntegrationState{}, err
		}
	case agentClientVSCode:
		userDir, reason := vsCodeUserConfigDir(executable("code"))
		if reason != "" || userDir == "" {
			return IntegrationState{}, fmt.Errorf("VS Code user config is unavailable: %s", reason)
		}
		path := filepath.Join(userDir, "mcp.json")
		entry := map[string]any{"command": mcpPath}
		if err := modifyJSONCClientConfig(path, []string{"servers"}, vsCodeServerID, entry, agentClientVSCode, mcpPath, connected); err != nil {
			return IntegrationState{}, err
		}
	default:
		return IntegrationState{}, fmt.Errorf("unsupported Agent client %q", clientID)
	}
	return m.IntegrationState(), nil
}

func runCodexMCPCommandError(codexPath, action, serverID string, mcpPath ...string) error {
	if codexPath == "" {
		return errors.New("Codex CLI is not installed")
	}
	args := []string{"mcp", action, serverID}
	if action == "add" {
		if len(mcpPath) != 1 || mcpPath[0] == "" {
			return errors.New("CyShell MCP executable is not installed")
		}
		args = append(args, "--", mcpPath[0])
	}
	output, err := exec.Command(codexPath, args...).CombinedOutput()
	if err != nil {
		if message := strings.TrimSpace(string(output)); message != "" {
			return fmt.Errorf("codex mcp %s failed: %s", action, message)
		}
		return fmt.Errorf("codex mcp %s failed: %w", action, err)
	}
	return nil
}

func inspectCodexServer(data []byte, serverID string, mcpPath string) (bool, string) {
	targetHeader := "mcp_servers." + serverID
	parentHeader := "mcp_servers"
	var targetLines []string
	var targetCount int
	var parentTarget bool
	targetSection := false
	parentSection := false
	for _, raw := range strings.Split(string(data), "\n") {
		line := strings.TrimSpace(stripTOMLComment(raw))
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, "[") {
			if !strings.HasSuffix(line, "]") {
				targetSection = false
				parentSection = false
				continue
			}
			header := strings.TrimSpace(strings.Trim(line, "[]"))
			header = strings.ReplaceAll(header, `"`, "")
			header = strings.ReplaceAll(header, "'", "")
			if strings.HasPrefix(line, "[[") && strings.Contains(header, targetHeader) {
				return false, "config_conflict"
			}
			targetSection = header == targetHeader
			parentSection = header == parentHeader
			if targetSection {
				targetCount++
			}
			if strings.HasPrefix(header, targetHeader+".") || strings.Contains(header, targetHeader) && !targetSection {
				return false, "config_conflict"
			}
			continue
		}
		if targetSection {
			targetLines = append(targetLines, line)
			continue
		}
		if parentSection {
			key, _, ok := strings.Cut(line, "=")
			if ok && strings.Trim(strings.TrimSpace(key), `"'`) == serverID {
				parentTarget = true
			}
		}
	}
	if targetCount > 1 || parentTarget {
		return false, "config_conflict"
	}
	if targetCount == 0 {
		for _, raw := range strings.Split(string(data), "\n") {
			line := strings.TrimSpace(stripTOMLComment(raw))
			if strings.Contains(line, targetHeader) || strings.Contains(line, serverID) && strings.Contains(line, "mcp_servers") {
				return false, "config_conflict"
			}
		}
		return false, ""
	}
	values := make(map[string]string)
	for _, line := range targetLines {
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			return false, "config_conflict"
		}
		key = strings.Trim(strings.TrimSpace(key), `"'`)
		if key != "command" && key != "args" {
			return false, "config_conflict"
		}
		if _, exists := values[key]; exists {
			return false, "config_conflict"
		}
		values[key] = strings.TrimSpace(value)
	}
	command, ok := tomlString(values["command"])
	if !ok {
		return false, "config_conflict"
	}
	if mcpPath == "" {
		return false, "server_missing"
	}
	if !isCyShellMCPCommand(command, mcpPath) {
		return false, "config_conflict"
	}
	if args, exists := values["args"]; exists && !tomlEmptyArray(args) {
		return false, "config_conflict"
	}
	return true, ""
}

func stripTOMLComment(line string) string {
	doubleQuoted, singleQuoted, escaped := false, false, false
	for index, char := range line {
		if escaped {
			escaped = false
			continue
		}
		if doubleQuoted && char == '\\' {
			escaped = true
			continue
		}
		if !singleQuoted && char == '"' {
			doubleQuoted = !doubleQuoted
			continue
		}
		if !doubleQuoted && char == '\'' {
			singleQuoted = !singleQuoted
			continue
		}
		if char == '#' && !doubleQuoted && !singleQuoted {
			return line[:index]
		}
	}
	return line
}

func tomlString(value string) (string, bool) {
	value = strings.TrimSpace(value)
	if len(value) < 2 {
		return "", false
	}
	if value[0] == '"' && value[len(value)-1] == '"' {
		decoded, err := strconv.Unquote(value)
		return decoded, err == nil
	}
	if value[0] == '\'' && value[len(value)-1] == '\'' {
		return value[1 : len(value)-1], true
	}
	return "", false
}

func tomlEmptyArray(value string) bool {
	value = strings.TrimSpace(value)
	return len(value) >= 2 && value[0] == '[' && value[len(value)-1] == ']' && strings.TrimSpace(value[1:len(value)-1]) == ""
}

func (m *Manager) writeTunnelCredentials(tunnelID, apiKey string, clear bool) error {
	path := m.tunnelCredentialsPath()
	if clear {
		if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
			return err
		}
		return nil
	}
	tunnelID = strings.TrimSpace(tunnelID)
	apiKey = strings.TrimSpace(apiKey)
	if tunnelID == "" && apiKey == "" {
		return nil
	}
	if tunnelID == "" || apiKey == "" {
		return errors.New("Tunnel ID and control-plane API key must be provided together")
	}
	if !strings.HasPrefix(tunnelID, "tunnel_") {
		return errors.New("Tunnel ID must start with tunnel_")
	}
	if strings.ContainsAny(tunnelID, "\r\n") || strings.ContainsAny(apiKey, "\r\n") {
		return errors.New("Tunnel credentials contain an invalid newline")
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	body := "CONTROL_PLANE_TUNNEL_ID=" + tunnelID + "\nCONTROL_PLANE_API_KEY=" + apiKey + "\n"
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, []byte(body), 0o600); err != nil {
		return err
	}
	if err := os.Chmod(tmp, 0o600); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, path)
}

func (m *Manager) writeUserUnits(cfg IntegrationConfig) error {
	dir := m.systemdUserDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}

	cyshellMCP := executable("cyshell-mcp")
	if cyshellMCP == "" {
		cyshellMCP = "/usr/local/bin/cyshell-mcp"
	}
	bridge := "[Unit]\nDescription=CyShell Agent MCP HTTP bridge\nAfter=cyshell.service\nWants=cyshell.service\n\n[Service]\nType=simple\nEnvironment=CYSHELL_MCP_HTTP_ADDR=127.0.0.1:7333\nEnvironment=CYSHELL_SOCKET=\n"
	if cfg.ExternalFallback {
		bridge += "Environment=CYSHELL_MCP_FALLBACK_URL=http://127.0.0.1:7331/mcp\n"
	}
	bridge += "ExecStart=" + cyshellMCP + "\nRestart=always\nRestartSec=1\nTimeoutStopSec=10\n\n[Install]\nWantedBy=default.target\n"
	if err := os.WriteFile(filepath.Join(dir, "cyshell-mcp-http.service"), []byte(bridge), 0o644); err != nil {
		return err
	}

	cycom := executable("cycomagent")
	if cycom == "" {
		cycom = "/usr/local/bin/cycomagent"
	}
	companion := "[Unit]\nDescription=CyCom companion fallback for CyShell Agent\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=simple\nExecStart=" + cycom + " -mode=http -addr=127.0.0.1:7331\nRestart=always\nRestartSec=2\nTimeoutStopSec=10\n\n[Install]\nWantedBy=default.target\n"
	if err := os.WriteFile(filepath.Join(dir, "cycomagent-fallback.service"), []byte(companion), 0o644); err != nil {
		return err
	}

	tunnel := executable("tunnel-client")
	if tunnel == "" {
		home, _ := os.UserHomeDir()
		tunnel = filepath.Join(home, ".local", "bin", "tunnel-client")
	}
	tunnelUnit := "[Unit]\nDescription=CyShell Agent ChatGPT Secure MCP Tunnel\nAfter=network-online.target cyshell-mcp-http.service\nWants=network-online.target cyshell-mcp-http.service\nStartLimitIntervalSec=60\nStartLimitBurst=10\n\n[Service]\nType=simple\nWorkingDirectory=%h\nEnvironment=MCP_SERVER_URL=http://127.0.0.1:7333/mcp\nEnvironment=HEALTH_LISTEN_ADDR=127.0.0.1:7332\nEnvironmentFile=" + m.tunnelCredentialsPath() + "\nExecStartPre=/bin/sh -c 'i=0; while ! /usr/bin/curl -fsS --max-time 1 http://127.0.0.1:7333/readyz >/dev/null 2>&1; do i=$((i+1)); [ \"$i\" -ge 60 ] && exit 1; sleep 1; done'\nExecStart=" + tunnel + " run --log.level=info --log.format=json\nRestart=always\nRestartSec=2\nTimeoutStopSec=15\n\n[Install]\nWantedBy=default.target\n"
	if err := os.WriteFile(filepath.Join(dir, "cycomagent-tunnel.service"), []byte(tunnelUnit), 0o644); err != nil {
		return err
	}
	return nil
}

func systemctlUser(args ...string) error {
	cmd := exec.Command("systemctl", append([]string{"--user"}, args...)...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		text := strings.TrimSpace(string(output))
		if text != "" {
			return fmt.Errorf("systemctl --user %s: %s", strings.Join(args, " "), text)
		}
		return fmt.Errorf("systemctl --user %s: %w", strings.Join(args, " "), err)
	}
	return nil
}

func serviceEnableNow(name string) error {
	return systemctlUser("enable", "--now", name)
}

func serviceDisableNow(name string) {
	_ = systemctlUser("disable", "--now", name)
	_ = systemctlUser("reset-failed", name)
}

func externalFallbackEndpointReady() bool {
	client := &http.Client{Timeout: 1200 * time.Millisecond}
	resp, err := client.Get("http://127.0.0.1:7331/readyz")
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode >= 200 && resp.StatusCode < 300
}

func (m *Manager) applyIntegrationServices(cfg IntegrationConfig) string {
	if err := systemctlUser("daemon-reload"); err != nil {
		return err.Error()
	}

	needsHTTP := cfg.Mode == integrationModeTunnel || cfg.Mode == integrationModeAPI
	if needsHTTP {
		if err := serviceEnableNow("cyshell-mcp-http.service"); err != nil {
			return err.Error()
		}
		// The generated unit may have changed environment such as
		// CYSHELL_MCP_FALLBACK_URL. enable --now does not restart an already
		// running unit, so explicitly restart the bridge to apply it.
		if err := systemctlUser("restart", "cyshell-mcp-http.service"); err != nil {
			return err.Error()
		}
	} else {
		serviceDisableNow("cyshell-mcp-http.service")
	}

	if needsHTTP && cfg.ExternalFallback && executable("cycomagent") != "" {
		if externalFallbackEndpointReady() {
			// A standalone/system CyCom already owns 7331 and is healthy. Reuse it
			// instead of starting a second companion that would fail with EADDRINUSE.
			serviceDisableNow("cycomagent-fallback.service")
		} else if err := serviceEnableNow("cycomagent-fallback.service"); err != nil {
			return err.Error()
		}
	} else {
		serviceDisableNow("cycomagent-fallback.service")
	}

	if cfg.Mode == integrationModeTunnel && executable("tunnel-client") != "" && envHasTunnelCredentials(m.tunnelCredentialsPath()) {
		if err := serviceEnableNow("cycomagent-tunnel.service"); err != nil {
			return err.Error()
		}
	} else {
		serviceDisableNow("cycomagent-tunnel.service")
	}

	return ""
}

func (m *Manager) ConfigureIntegration(mode string, externalFallback bool, agentAppEnabled bool, tunnelID string, tunnelAPIKey string, clearTunnelCredentials bool) (IntegrationState, error) {
	normalized, err := normalizeIntegrationMode(mode)
	if err != nil {
		return IntegrationState{}, err
	}
	cfg := IntegrationConfig{
		Version:          1,
		Mode:             normalized,
		ExternalFallback: externalFallback,
		AgentAppEnabled:  agentAppEnabled,
	}
	if err := m.writeTunnelCredentials(tunnelID, tunnelAPIKey, clearTunnelCredentials); err != nil {
		return IntegrationState{}, err
	}
	if err := m.persistIntegrationConfig(cfg); err != nil {
		return IntegrationState{}, err
	}
	if err := m.writeUserUnits(cfg); err != nil {
		return IntegrationState{}, err
	}
	lastError := m.applyIntegrationServices(cfg)
	state := m.IntegrationState()
	state.LastError = lastError
	return state, nil
}
