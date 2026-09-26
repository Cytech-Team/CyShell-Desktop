package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/utils"
)

const (
	protocolLatest    = "2026-07-28"
	protocolLegacy    = "2025-11-25"
	maxMessageBytes   = 8 << 20
	maxIPCMessageSize = 96 << 20
)

type rpcRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type rpcResponse struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Result  any             `json:"result,omitempty"`
	Error   *rpcError       `json:"error,omitempty"`
}

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

type ipcRequest struct {
	ID     int            `json:"id"`
	Method string         `json:"method"`
	Params map[string]any `json:"params"`
}

type ipcResponse struct {
	ID     int             `json:"id"`
	Result json.RawMessage `json:"result"`
	Error  string          `json:"error"`
}

type ipcCallFunc func(method string, params map[string]any) (any, error)

type mcpClientInfo struct {
	Name    string `json:"name"`
	Version string `json:"version,omitempty"`
}

func main() {
	if maybeServeHTTP() {
		return
	}
	if err := run(os.Stdin, os.Stdout, callShell); err != nil {
		fmt.Fprintln(os.Stderr, "cyshell-mcp:", err)
		os.Exit(1)
	}
}

func run(in io.Reader, out io.Writer, call ipcCallFunc) error {
	scanner := bufio.NewScanner(in)
	scanner.Buffer(make([]byte, 64*1024), maxMessageBytes)
	encoder := json.NewEncoder(out)
	clientInfo := mcpClientInfo{Name: "External MCP client"}
	for scanner.Scan() {
		line := scanner.Bytes()
		if len(strings.TrimSpace(string(line))) == 0 {
			continue
		}
		var req rpcRequest
		if err := json.Unmarshal(line, &req); err != nil {
			if err := encoder.Encode(rpcResponse{JSONRPC: "2.0", Error: &rpcError{Code: -32700, Message: "parse error", Data: err.Error()}}); err != nil {
				return err
			}
			continue
		}
		if req.JSONRPC != "2.0" || req.Method == "" {
			if err := encoder.Encode(rpcResponse{JSONRPC: "2.0", ID: req.ID, Error: &rpcError{Code: -32600, Message: "invalid request"}}); err != nil {
				return err
			}
			continue
		}
		// MCP notifications intentionally receive no response.
		if len(req.ID) == 0 || string(req.ID) == "null" {
			continue
		}
		if req.Method == "initialize" {
			clientInfo = parseMCPClientInfo(req.Params)
		}
		result, rpcErr := dispatchWithClient(req, call, clientInfo)
		response := rpcResponse{JSONRPC: "2.0", ID: req.ID, Result: result, Error: rpcErr}
		if rpcErr != nil {
			response.Result = nil
		}
		if err := encoder.Encode(response); err != nil {
			return err
		}
	}
	return scanner.Err()
}

func dispatch(req rpcRequest, call ipcCallFunc) (any, *rpcError) {
	return dispatchWithClient(req, call, mcpClientInfo{Name: "External MCP client"})
}

func dispatchWithClient(req rpcRequest, call ipcCallFunc, clientInfo mcpClientInfo) (any, *rpcError) {
	switch req.Method {
	case "initialize":
		var params struct {
			ProtocolVersion string `json:"protocolVersion"`
		}
		_ = json.Unmarshal(req.Params, &params)
		version := params.ProtocolVersion
		if version == "" {
			version = protocolLatest
		}
		return map[string]any{
			"protocolVersion": version,
			"capabilities":    map[string]any{"tools": map[string]any{}},
			"serverInfo":      map[string]any{"name": "CyShell Desktop", "version": "embedded"},
			"instructions":    "CyCom is embedded in CyShell. Prefer shell semantic tools before computer-use fallbacks.",
		}, nil

	case "server/discover":
		return map[string]any{
			"resultType":        "complete",
			"supportedVersions": []string{protocolLatest, protocolLegacy, "2025-06-18", "2025-03-26"},
			"capabilities":      map[string]any{"tools": map[string]any{}},
			"instructions":      "CyCom is embedded in CyShell Desktop.",
			"ttlMs":             300000,
			"cacheScope":        "public",
		}, nil

	case "ping":
		return map[string]any{}, nil

	case "tools/list":
		value, err := call("cycom.tools.list", nil)
		if err != nil {
			return nil, &rpcError{Code: -32001, Message: "CyShell Agent unavailable", Data: err.Error()}
		}
		return map[string]any{"tools": value}, nil

	case "tools/call":
		var params struct {
			Name      string         `json:"name"`
			Arguments map[string]any `json:"arguments"`
		}
		if err := json.Unmarshal(req.Params, &params); err != nil || strings.TrimSpace(params.Name) == "" {
			return nil, &rpcError{Code: -32602, Message: "invalid tools/call parameters"}
		}
		if params.Arguments == nil {
			params.Arguments = map[string]any{}
		}
		reason, _ := params.Arguments["reason"].(string)
		if strings.TrimSpace(reason) == "" {
			return map[string]any{
				"content": []map[string]any{{"type": "text", "text": "reason is required for CyShell Agent tool calls"}},
				"isError": true,
			}, nil
		}
		clientInfo = normalizeMCPClientInfo(clientInfo)
		value, err := call("cycom.tools.call", map[string]any{
			"name":      params.Name,
			"reason":    reason,
			"arguments": params.Arguments,
			"origin": map[string]any{
				"kind":    "mcp",
				"name":    clientInfo.Name,
				"version": clientInfo.Version,
			},
		})
		if err != nil {
			return map[string]any{
				"content": []map[string]any{{"type": "text", "text": err.Error()}},
				"isError": true,
			}, nil
		}
		text, _ := json.Marshal(value)
		return map[string]any{
			"content":           []map[string]any{{"type": "text", "text": string(text)}},
			"structuredContent": value,
			"isError":           false,
		}, nil

	default:
		return nil, &rpcError{Code: -32601, Message: "method not found: " + req.Method}
	}
}

func parseMCPClientInfo(raw json.RawMessage) mcpClientInfo {
	var params struct {
		ClientInfo mcpClientInfo `json:"clientInfo"`
	}
	if json.Unmarshal(raw, &params) != nil {
		return mcpClientInfo{Name: "External MCP client"}
	}
	return normalizeMCPClientInfo(params.ClientInfo)
}

func normalizeMCPClientInfo(info mcpClientInfo) mcpClientInfo {
	info.Name = strings.Join(strings.Fields(info.Name), " ")
	info.Version = strings.Join(strings.Fields(info.Version), " ")
	if info.Name == "" {
		info.Name = "External MCP client"
	}
	if len([]rune(info.Name)) > 80 {
		info.Name = string([]rune(info.Name)[:80])
	}
	if len([]rune(info.Version)) > 40 {
		info.Version = string([]rune(info.Version)[:40])
	}
	return info
}

func callShell(method string, params map[string]any) (any, error) {
	socketPath, err := locateSocket()
	if err != nil {
		return nil, err
	}
	conn, err := net.DialTimeout("unix", socketPath, 2*time.Second)
	if err != nil {
		return nil, fmt.Errorf("connect to CyShell core: %w", err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(180 * time.Second))

	scanner := bufio.NewScanner(conn)
	scanner.Buffer(make([]byte, 64*1024), maxIPCMessageSize)
	if !scanner.Scan() {
		return nil, errors.New("CyShell core did not send an IPC greeting")
	}
	if params == nil {
		params = map[string]any{}
	}
	if err := json.NewEncoder(conn).Encode(ipcRequest{ID: 1, Method: method, Params: params}); err != nil {
		return nil, err
	}
	if !scanner.Scan() {
		if err := scanner.Err(); err != nil {
			return nil, err
		}
		return nil, errors.New("CyShell core closed the IPC connection")
	}
	var response ipcResponse
	if err := json.Unmarshal(scanner.Bytes(), &response); err != nil {
		return nil, fmt.Errorf("decode CyShell IPC response: %w", err)
	}
	if response.Error != "" {
		return nil, errors.New(response.Error)
	}
	if len(response.Result) == 0 || string(response.Result) == "null" {
		return nil, nil
	}
	var value any
	if err := json.Unmarshal(response.Result, &value); err != nil {
		return nil, fmt.Errorf("decode CyShell IPC result: %w", err)
	}
	return value, nil
}

func locateSocket() (string, error) {
	if explicit := strings.TrimSpace(os.Getenv("CYSHELL_SOCKET")); explicit != "" {
		return explicit, nil
	}
	runtimeDir := utils.RuntimeDir()
	for _, name := range []string{"cyshell.sock", "danklinux.sock"} {
		path := filepath.Join(runtimeDir, name)
		if info, err := os.Stat(path); err == nil && info.Mode()&os.ModeSocket != 0 {
			return path, nil
		}
	}
	var candidates []string
	for _, pattern := range []string{"cyshell-*.sock", "danklinux-*.sock"} {
		matches, _ := filepath.Glob(filepath.Join(runtimeDir, pattern))
		candidates = append(candidates, matches...)
	}
	sort.SliceStable(candidates, func(i, j int) bool {
		ai, errI := os.Stat(candidates[i])
		aj, errJ := os.Stat(candidates[j])
		if errI != nil {
			return false
		}
		if errJ != nil {
			return true
		}
		return ai.ModTime().After(aj.ModTime())
	})
	for _, path := range candidates {
		if info, err := os.Stat(path); err == nil && info.Mode()&os.ModeSocket != 0 {
			return path, nil
		}
	}
	return "", fmt.Errorf("CyShell core socket not found in %s; set CYSHELL_SOCKET to override", runtimeDir)
}
