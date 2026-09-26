package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

func TestDispatchToolsListUsesEmbeddedShellIPC(t *testing.T) {
	call := func(method string, params map[string]any) (any, error) {
		if method != "cycom.tools.list" {
			t.Fatalf("method = %q", method)
		}
		return []any{map[string]any{"name": "shell_get_state", "inputSchema": map[string]any{"type": "object"}}}, nil
	}
	result, rpcErr := dispatch(rpcRequest{Method: "tools/list"}, call)
	if rpcErr != nil {
		t.Fatal(rpcErr)
	}
	out := result.(map[string]any)
	if len(out["tools"].([]any)) != 1 {
		t.Fatalf("unexpected tools list: %#v", result)
	}
}

func TestDispatchToolCallForwardsReason(t *testing.T) {
	call := func(method string, params map[string]any) (any, error) {
		if method != "cycom.tools.call" {
			t.Fatalf("method = %q", method)
		}
		if params["name"] != "shell_get_state" || params["reason"] != "inspect desktop" {
			t.Fatalf("unexpected params: %#v", params)
		}
		return map[string]any{"shell": "CyShell Desktop"}, nil
	}
	params, _ := json.Marshal(map[string]any{
		"name":      "shell_get_state",
		"arguments": map[string]any{"reason": "inspect desktop"},
	})
	result, rpcErr := dispatch(rpcRequest{Method: "tools/call", Params: params}, call)
	if rpcErr != nil {
		t.Fatal(rpcErr)
	}
	if result.(map[string]any)["isError"] != false {
		t.Fatalf("unexpected tool response: %#v", result)
	}
}

func TestStdioInitialize(t *testing.T) {
	input := strings.NewReader(`{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}` + "\n")
	var output bytes.Buffer
	if err := run(input, &output, func(string, map[string]any) (any, error) { return nil, nil }); err != nil {
		t.Fatal(err)
	}
	line, err := bufio.NewReader(&output).ReadBytes('\n')
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(line, []byte(`"serverInfo"`)) || !bytes.Contains(line, []byte(`"CyShell Desktop"`)) {
		t.Fatalf("unexpected initialize response: %s", line)
	}
}

func TestStdioToolCallAttributesInitializedMCPClient(t *testing.T) {
	input := strings.NewReader(
		`{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2026-07-28","clientInfo":{"name":"Claude Desktop","version":"9.9"}}}` + "\n" +
			`{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"shell_get_state","arguments":{"reason":"inspect desktop"}}}` + "\n",
	)
	var output bytes.Buffer
	calls := 0
	call := func(method string, params map[string]any) (any, error) {
		if method != "cycom.tools.call" {
			if method == "cycom.tools.list" {
				return []any{}, nil
			}
			return nil, nil
		}
		calls++
		origin, ok := params["origin"].(map[string]any)
		if !ok {
			t.Fatalf("origin missing: %#v", params)
		}
		if origin["kind"] != "mcp" || origin["name"] != "Claude Desktop" || origin["version"] != "9.9" {
			t.Fatalf("unexpected MCP origin: %#v", origin)
		}
		return map[string]any{"ok": true}, nil
	}
	if err := run(input, &output, call); err != nil {
		t.Fatal(err)
	}
	if calls != 1 {
		t.Fatalf("tool calls = %d, want 1", calls)
	}
}

func TestParseMCPClientInfoSanitizesWhitespace(t *testing.T) {
	raw := json.RawMessage(`{"clientInfo":{"name":"  Example   Agent  ","version":" 1.0  beta "}}`)
	info := parseMCPClientInfo(raw)
	if info.Name != "Example Agent" || info.Version != "1.0 beta" {
		t.Fatalf("unexpected client info: %#v", info)
	}
}
