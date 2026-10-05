package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"
)

const maxHTTPBodyBytes = 8 << 20

type httpBridge struct {
	mu     sync.RWMutex
	client mcpClientInfo
}

func maybeServeHTTP() bool {
	addr := strings.TrimSpace(os.Getenv("CYSHELL_MCP_HTTP_ADDR"))
	if addr == "" {
		return false
	}
	if !isLoopbackListenAddr(addr) {
		fmt.Fprintf(os.Stderr, "cyshell-mcp: refusing non-loopback HTTP bind %q\n", addr)
		os.Exit(2)
	}

	bridge := &httpBridge{client: mcpClientInfo{Name: "External MCP client"}}
	mux := http.NewServeMux()
	mux.HandleFunc("/mcp", bridge.handleMCP)
	mux.HandleFunc("/livez", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"ok":                 true,
			"transport":          "cyshell-agent-gateway",
			"fallbackConfigured": fallbackMCPURL() != "",
		})
	})
	mux.HandleFunc("/readyz", func(w http.ResponseWriter, _ *http.Request) {
		tools, err := callShell("cycom.tools.list", nil)
		if err == nil {
			count := 0
			if list, ok := tools.([]any); ok {
				count = len(list)
			}
			writeJSON(w, http.StatusOK, map[string]any{"ok": true, "backend": "cyshell-embedded", "toolCount": count})
			return
		}
		if fallbackReady() {
			writeJSON(w, http.StatusOK, map[string]any{"ok": true, "backend": "cycom-companion-fallback"})
			return
		}
		writeJSON(w, http.StatusServiceUnavailable, map[string]any{"ok": false, "error": err.Error()})
	})

	srv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       90 * time.Second,
		MaxHeaderBytes:    1 << 20,
	}
	fmt.Fprintf(os.Stderr, "cyshell-mcp: embedded HTTP transport listening on http://%s/mcp\n", addr)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		fmt.Fprintln(os.Stderr, "cyshell-mcp:", err)
		os.Exit(1)
	}
	return true
}

func (b *httpBridge) handleMCP(w http.ResponseWriter, r *http.Request) {
	if !validHTTPOrigin(r) {
		http.Error(w, "forbidden origin", http.StatusForbidden)
		return
	}
	if fallbackMCPURL() != "" && !embeddedMCPReady() {
		if proxyFallbackMCP(w, r) {
			return
		}
	}
	switch r.Method {
	case http.MethodPost:
		b.handlePOST(w, r)
	case http.MethodGet:
		serveLegacyProbe(w, r)
	default:
		w.Header().Set("Allow", "POST, GET")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func fallbackMCPURL() string {
	raw := strings.TrimSpace(os.Getenv("CYSHELL_MCP_FALLBACK_URL"))
	if raw == "" {
		return ""
	}
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "http" || u.Host == "" {
		return ""
	}
	host := strings.TrimSpace(u.Hostname())
	if strings.EqualFold(host, "localhost") {
		return u.String()
	}
	ip := net.ParseIP(host)
	if ip == nil || !ip.IsLoopback() {
		return ""
	}
	return u.String()
}

func embeddedMCPReady() bool {
	_, err := callShell("cycom.tools.list", nil)
	return err == nil
}

func fallbackReady() bool {
	raw := fallbackMCPURL()
	if raw == "" {
		return false
	}
	u, err := url.Parse(raw)
	if err != nil {
		return false
	}
	u.Path = "/readyz"
	u.RawQuery = ""
	client := &http.Client{Timeout: 1200 * time.Millisecond}
	resp, err := client.Get(u.String())
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode >= 200 && resp.StatusCode < 300
}

func proxyFallbackMCP(w http.ResponseWriter, r *http.Request) bool {
	raw := fallbackMCPURL()
	if raw == "" {
		return false
	}

	var body []byte
	var err error
	if r.Body != nil {
		r.Body = http.MaxBytesReader(w, r.Body, maxHTTPBodyBytes)
		body, err = io.ReadAll(r.Body)
		if err != nil {
			return false
		}
		_ = r.Body.Close()
	}

	req, err := http.NewRequestWithContext(r.Context(), r.Method, raw, bytes.NewReader(body))
	if err != nil {
		return false
	}
	for _, name := range []string{
		"Content-Type",
		"Accept",
		"Authorization",
		"X-CyCom-Token",
		"MCP-Protocol-Version",
		"Mcp-Method",
		"Mcp-Name",
	} {
		if value := r.Header.Get(name); value != "" {
			req.Header.Set(name, value)
		}
	}

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()

	for _, name := range []string{"Content-Type", "Cache-Control", "X-CyCom-Compatibility"} {
		if value := resp.Header.Get(name); value != "" {
			w.Header().Set(name, value)
		}
	}
	w.Header().Set("X-CyShell-Agent-Backend", "cycom-companion")
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(w, resp.Body)
	return true
}

func (b *httpBridge) handlePOST(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, maxHTTPBodyBytes)
	defer r.Body.Close()
	data, err := io.ReadAll(r.Body)
	if err != nil {
		writeRPCError(w, nil, http.StatusBadRequest, -32700, "invalid request body", err.Error())
		return
	}
	var req rpcRequest
	if err := json.Unmarshal(data, &req); err != nil {
		writeRPCError(w, nil, http.StatusBadRequest, -32700, "parse error", err.Error())
		return
	}
	if req.JSONRPC != "2.0" || strings.TrimSpace(req.Method) == "" {
		writeRPCError(w, req.ID, http.StatusBadRequest, -32600, "invalid request", nil)
		return
	}
	modern, err := detectHTTPProtocol(r, req)
	if err != nil {
		writeRPCError(w, req.ID, http.StatusBadRequest, -32020, err.Error(), nil)
		return
	}
	if len(req.ID) == 0 || string(req.ID) == "null" {
		w.WriteHeader(http.StatusAccepted)
		return
	}

	if req.Method == "initialize" {
		b.mu.Lock()
		b.client = parseMCPClientInfo(req.Params)
		b.mu.Unlock()
	}
	b.mu.RLock()
	client := b.client
	b.mu.RUnlock()

	result, rpcErr := dispatchWithClient(req, callShell, client)
	if rpcErr == nil && modern {
		result = addModernHTTPMeta(req.Method, result)
	}
	status := http.StatusOK
	if modern && rpcErr != nil && rpcErr.Code == -32601 {
		status = http.StatusNotFound
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	resp := rpcResponse{JSONRPC: "2.0", ID: req.ID, Result: result, Error: rpcErr}
	if rpcErr != nil {
		resp.Result = nil
	}
	_ = json.NewEncoder(w).Encode(resp)
}

func detectHTTPProtocol(r *http.Request, req rpcRequest) (bool, error) {
	header := strings.TrimSpace(r.Header.Get("MCP-Protocol-Version"))
	var env struct {
		Meta map[string]json.RawMessage `json:"_meta"`
	}
	_ = json.Unmarshal(req.Params, &env)
	var bodyVersion string
	if raw := env.Meta["io.modelcontextprotocol/protocolVersion"]; len(raw) > 0 {
		_ = json.Unmarshal(raw, &bodyVersion)
	}
	modern := header == protocolLatest || bodyVersion == protocolLatest || req.Method == "server/discover"
	if header != "" && header != protocolLatest && header != protocolLegacy && header != "2025-06-18" && header != "2025-03-26" {
		return modern, fmt.Errorf("unsupported protocol version %s", header)
	}
	if modern && header != "" && bodyVersion != "" && header != bodyVersion {
		return true, fmt.Errorf("MCP-Protocol-Version header does not match request _meta")
	}
	return modern, nil
}

func addModernHTTPMeta(method string, result any) any {
	m, ok := result.(map[string]any)
	if !ok || m == nil {
		return result
	}
	m["_meta"] = map[string]any{
		"io.modelcontextprotocol/serverInfo": map[string]any{"name": "CyShell Desktop", "version": "embedded"},
	}
	switch method {
	case "server/discover":
		m["resultType"] = "complete"
		m["ttlMs"] = 300000
		m["cacheScope"] = "public"
	case "tools/list":
		m["resultType"] = "complete"
		m["ttlMs"] = 30000
		m["cacheScope"] = "public"
	case "tools/call":
		m["resultType"] = "complete"
	}
	return m
}

func validHTTPOrigin(r *http.Request) bool {
	origin := strings.TrimSpace(r.Header.Get("Origin"))
	if origin == "" {
		return true
	}
	u, err := url.Parse(origin)
	if err != nil || u.Scheme == "" || u.Host == "" {
		return false
	}
	host := strings.TrimSpace(u.Hostname())
	if strings.EqualFold(host, "localhost") {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

func isLoopbackListenAddr(addr string) bool {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return false
	}
	if strings.EqualFold(host, "localhost") {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

func writeRPCError(w http.ResponseWriter, id json.RawMessage, status, code int, message string, data any) {
	writeJSON(w, status, rpcResponse{JSONRPC: "2.0", ID: id, Error: &rpcError{Code: code, Message: message, Data: data}})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func serveLegacyProbe(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming unsupported", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.WriteHeader(http.StatusOK)
	_, _ = io.WriteString(w, ": CyShell embedded MCP legacy probe compatibility\n\n")
	flusher.Flush()

	ticker := time.NewTicker(25 * time.Second)
	deadline := time.NewTimer(60 * time.Second)
	defer ticker.Stop()
	defer deadline.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case <-deadline.C:
			return
		case <-ticker.C:
			_, _ = io.WriteString(w, ": keepalive\n\n")
			flusher.Flush()
		}
	}
}
