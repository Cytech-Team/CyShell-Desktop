package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const maxResponseBytes = 64 << 20

type request struct {
	ID     int            `json:"id"`
	Method string         `json:"method"`
	Params map[string]any `json:"params"`
}

type response struct {
	ID     int             `json:"id"`
	Result json.RawMessage `json:"result"`
	Error  string          `json:"error"`
}

type input struct {
	Reason string `json:"reason"`
}

type desktopState struct {
	SchemaVersion int            `json:"schema_version"`
	Shell         string         `json:"shell"`
	CapturedAt    string         `json:"captured_at"`
	Server        any            `json:"server"`
	Services      map[string]any `json:"services"`
	Errors        map[string]any `json:"errors,omitempty"`
}

func main() {
	if len(os.Args) != 2 || os.Args[1] != "desktop-state" {
		fail(fmt.Errorf("usage: cyshell-agent-bridge desktop-state"))
	}
	var in input
	if err := json.NewDecoder(os.Stdin).Decode(&in); err != nil {
		fail(fmt.Errorf("decode input: %w", err))
	}
	if strings.TrimSpace(in.Reason) == "" {
		fail(errors.New("reason is required"))
	}

	socketPath, err := locateSocket()
	if err != nil {
		fail(err)
	}
	state, err := readDesktopState(socketPath)
	if err != nil {
		fail(err)
	}
	if err := json.NewEncoder(os.Stdout).Encode(state); err != nil {
		fail(err)
	}
}

func locateSocket() (string, error) {
	if path := strings.TrimSpace(os.Getenv("CYSHELL_SOCKET")); path != "" {
		return path, nil
	}
	runtimeDir := strings.TrimSpace(os.Getenv("XDG_RUNTIME_DIR"))
	if runtimeDir == "" {
		runtimeDir = fmt.Sprintf("/run/user/%d", os.Getuid())
	}
	for _, exact := range []string{"cyshell.sock", "danklinux.sock"} {
		path := filepath.Join(runtimeDir, exact)
		if info, err := os.Stat(path); err == nil && info.Mode()&os.ModeSocket != 0 {
			return path, nil
		}
	}
	var matches []string
	for _, pattern := range []string{"cyshell-*.sock", "danklinux-*.sock"} {
		found, _ := filepath.Glob(filepath.Join(runtimeDir, pattern))
		matches = append(matches, found...)
	}
	sort.Strings(matches)
	for _, path := range matches {
		if info, err := os.Stat(path); err == nil && info.Mode()&os.ModeSocket != 0 {
			return path, nil
		}
	}
	return "", fmt.Errorf("CyShell IPC socket not found in %s; set CYSHELL_SOCKET to override", runtimeDir)
}

func readDesktopState(socketPath string) (desktopState, error) {
	serverInfo, err := call(socketPath, "getServerInfo", nil)
	if err != nil {
		return desktopState{}, fmt.Errorf("getServerInfo: %w", err)
	}

	caps := capabilitySet(serverInfo)
	services := make(map[string]any)
	errs := make(map[string]any)
	methods := []struct {
		capability string
		name       string
		method     string
	}{
		{"network", "network", "network.getState"},
		{"bluetooth", "bluetooth", "bluetooth.getState"},
		{"brightness", "brightness", "brightness.getState"},
		{"wlroutput", "displays", "wlroutput.getState"},
		{"loginctl", "session", "loginctl.getState"},
	}
	for _, item := range methods {
		if !caps[item.capability] {
			continue
		}
		value, callErr := call(socketPath, item.method, nil)
		if callErr != nil {
			errs[item.name] = callErr.Error()
			continue
		}
		services[item.name] = value
	}

	state := desktopState{
		SchemaVersion: 1,
		Shell:         "CyShell Desktop",
		CapturedAt:    time.Now().UTC().Format(time.RFC3339Nano),
		Server:        serverInfo,
		Services:      services,
	}
	if len(errs) > 0 {
		state.Errors = errs
	}
	return state, nil
}

func capabilitySet(serverInfo any) map[string]bool {
	out := make(map[string]bool)
	value, ok := serverInfo.(map[string]any)
	if !ok {
		return out
	}
	caps, ok := value["capabilities"].([]any)
	if !ok {
		return out
	}
	for _, capValue := range caps {
		if capName, ok := capValue.(string); ok {
			out[capName] = true
		}
	}
	return out
}

func call(socketPath, method string, params map[string]any) (any, error) {
	conn, err := net.DialTimeout("unix", socketPath, 2*time.Second)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(5 * time.Second))

	reader := bufio.NewReaderSize(conn, 64*1024)
	if _, err := readLineLimited(reader, maxResponseBytes); err != nil {
		return nil, fmt.Errorf("read server greeting: %w", err)
	}
	if params == nil {
		params = map[string]any{}
	}
	if err := json.NewEncoder(conn).Encode(request{ID: 1, Method: method, Params: params}); err != nil {
		return nil, err
	}
	line, err := readLineLimited(reader, maxResponseBytes)
	if err != nil {
		return nil, err
	}
	var resp response
	if err := json.Unmarshal(line, &resp); err != nil {
		return nil, fmt.Errorf("decode response for %s: %w", method, err)
	}
	if resp.Error != "" {
		return nil, errors.New(resp.Error)
	}
	if len(resp.Result) == 0 || string(resp.Result) == "null" {
		return nil, nil
	}
	var value any
	if err := json.Unmarshal(resp.Result, &value); err != nil {
		return nil, fmt.Errorf("decode result for %s: %w", method, err)
	}
	return value, nil
}

func readLineLimited(reader *bufio.Reader, limit int) ([]byte, error) {
	var out []byte
	for {
		part, isPrefix, err := reader.ReadLine()
		if err != nil {
			return nil, err
		}
		if len(out)+len(part) > limit {
			return nil, fmt.Errorf("IPC response exceeds %d bytes", limit)
		}
		out = append(out, part...)
		if !isPrefix {
			return out, nil
		}
	}
}

func fail(err error) {
	_ = json.NewEncoder(os.Stdout).Encode(map[string]any{"error": err.Error()})
	os.Exit(1)
}
