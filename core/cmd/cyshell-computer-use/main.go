package main

import (
	"bufio"
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	"image/draw"
	"image/jpeg"
	"image/png"
	"io"
	"math"
	"net"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	xdraw "golang.org/x/image/draw"

	"github.com/Cytech-Team/CyShell-Desktop/core/internal/utils"
)

const (
	protocolVersion   = "2024-11-05"
	maxMessageBytes   = 8 << 20
	maxIPCMessageSize = 96 << 20
)

type ipcCallFunc func(method string, params map[string]any) (any, error)

type shellWindow struct {
	ID         uint64
	Index      int
	AppID      string
	Title      string
	PID        int
	Active     bool
	Minimized  bool
	Maximized  bool
	Fullscreen bool
	Screens    []string
}

type rect struct {
	X int
	Y int
	W int
	H int
}

func (r rect) valid() bool {
	return r.W > 0 && r.H > 0
}

type outputGeometry struct {
	Name   string
	X      int
	Y      int
	Width  int
	Height int
	Scale  float64
}

func (o outputGeometry) valid() bool {
	return o.Width > 0 && o.Height > 0
}

type backend struct {
	call ipcCallFunc

	mu      sync.Mutex
	nextID  uint64
	idByKey map[string]uint64
	windows map[uint64]shellWindow
}

func newBackend(call ipcCallFunc) *backend {
	return &backend{
		call:    call,
		nextID:  1,
		idByKey: map[string]uint64{},
		windows: map[uint64]shellWindow{},
	}
}

func main() {
	mode := "mcp"
	if len(os.Args) > 1 {
		mode = os.Args[1]
	}
	b := newBackend(callShell)
	switch mode {
	case "mcp":
		if err := b.serve(os.Stdin, os.Stdout); err != nil {
			fmt.Fprintln(os.Stderr, "cyshell-computer-use:", err)
			os.Exit(1)
		}
	case "doctor":
		windows, err := b.refreshWindows()
		if err != nil {
			fmt.Fprintln(os.Stderr, "CYSHELL_COMPUTER_USE_NOT_READY:", err)
			os.Exit(1)
		}
		socket, _ := locateSocket()
		fmt.Printf("CYSHELL_COMPUTER_USE_READY windows=%d socket=%s\n", len(windows), socket)
	default:
		fmt.Fprintln(os.Stderr, "usage: cyshell-computer-use [mcp|doctor]")
		os.Exit(2)
	}
}

func (b *backend) serve(in io.Reader, out io.Writer) error {
	scanner := bufio.NewScanner(in)
	scanner.Buffer(make([]byte, 64*1024), maxMessageBytes)
	enc := json.NewEncoder(out)

	for scanner.Scan() {
		line := bytes.TrimSpace(scanner.Bytes())
		if len(line) == 0 {
			continue
		}

		var req map[string]json.RawMessage
		if err := json.Unmarshal(line, &req); err != nil {
			if err := enc.Encode(rpcErrorResponse(nil, -32700, "parse error", err.Error())); err != nil {
				return err
			}
			continue
		}

		method := rawString(req["method"])
		id, hasID := req["id"]
		if rawString(req["jsonrpc"]) != "2.0" || method == "" {
			if hasID {
				if err := enc.Encode(rpcErrorResponse(id, -32600, "invalid request", nil)); err != nil {
					return err
				}
			}
			continue
		}

		if !hasID || string(id) == "null" {
			continue
		}

		result, rpcErr := b.dispatch(method, req["params"])
		var response map[string]any
		if rpcErr != nil {
			response = rpcErrorResponse(id, rpcErr.code, rpcErr.message, rpcErr.data)
		} else {
			response = map[string]any{
				"jsonrpc": "2.0",
				"id":      json.RawMessage(id),
				"result":  result,
			}
		}
		if err := enc.Encode(response); err != nil {
			return err
		}
	}
	return scanner.Err()
}

type rpcFailure struct {
	code    int
	message string
	data    any
}

func (b *backend) dispatch(method string, rawParams json.RawMessage) (any, *rpcFailure) {
	switch method {
	case "initialize":
		version := protocolVersion
		var params map[string]json.RawMessage
		if json.Unmarshal(rawParams, &params) == nil {
			if requested := rawString(params["protocolVersion"]); requested != "" {
				version = requested
			}
		}
		return map[string]any{
			"protocolVersion": version,
			"capabilities":    map[string]any{"tools": map[string]any{}},
			"serverInfo":      map[string]any{"name": "CyShell Computer Use", "version": "1"},
			"instructions":    "Linux Computer Use is provided by CyShell Desktop. CyShell resolves windows and permissions; AT-SPI is used only as an application accessibility sensor.",
		}, nil
	case "ping":
		return map[string]any{}, nil
	case "tools/list":
		return map[string]any{"tools": toolDefinitions()}, nil
	case "tools/call":
		params, err := decodeMap(rawParams)
		if err != nil {
			return nil, &rpcFailure{code: -32602, message: "invalid tools/call parameters", data: err.Error()}
		}
		name, _ := params["name"].(string)
		args, _ := params["arguments"].(map[string]any)
		if strings.TrimSpace(name) == "" {
			return nil, &rpcFailure{code: -32602, message: "tool name is required"}
		}
		if args == nil {
			args = map[string]any{}
		}
		result, err := b.callNativeTool(name, args)
		if err != nil {
			return toolError(err), nil
		}
		return result, nil
	default:
		return nil, &rpcFailure{code: -32601, message: "method not found: " + method}
	}
}

func toolDefinitions() []map[string]any {
	names := []string{"list_windows", "get_app_state", "screenshot", "click", "scroll", "press_key", "type_text"}
	out := make([]map[string]any, 0, len(names))
	for _, name := range names {
		out = append(out, map[string]any{
			"name":        name,
			"description": "CyShell-backed Linux Computer Use compatibility tool.",
			"inputSchema": map[string]any{"type": "object", "additionalProperties": true},
		})
	}
	return out
}

func (b *backend) callNativeTool(name string, args map[string]any) (any, error) {
	switch name {
	case "list_windows":
		return b.listWindowsTool()
	case "get_app_state":
		return b.getAppStateTool(args)
	case "screenshot":
		return b.screenshotTool(args)
	case "click":
		return b.clickTool(args)
	case "scroll":
		return b.scrollTool(args)
	case "press_key":
		return b.pressKeyTool(args)
	case "type_text":
		return b.typeTextTool(args)
	default:
		return nil, fmt.Errorf("unsupported native Linux Computer Use tool: %s", name)
	}
}

func (b *backend) listWindowsTool() (any, error) {
	windows, err := b.refreshWindows()
	if err != nil {
		return nil, err
	}
	items := make([]map[string]any, 0, len(windows))
	for _, w := range windows {
		item := map[string]any{
			"window_id":  w.ID,
			"title":      w.Title,
			"app_id":     w.AppID,
			"wm_class":   w.AppID,
			"pid":        w.PID,
			"focused":    w.Active,
			"minimized":  w.Minimized,
			"maximized":  w.Maximized,
			"fullscreen": w.Fullscreen,
			"screens":    w.Screens,
			"backend":    "cyshell",
		}
		items = append(items, item)
	}
	return toolSuccess(map[string]any{
		"windows": items,
		"backend": "cyshell",
	}), nil
}

func (b *backend) getAppStateTool(args map[string]any) (any, error) {
	w, err := b.resolveWindow(args)
	if err != nil {
		return nil, err
	}

	maxNodes := intArg(args, "max_nodes", 400)
	if maxNodes < 1 {
		maxNodes = 1
	}
	if maxNodes > 2000 {
		maxNodes = 2000
	}
	maxDepth := intArg(args, "max_depth", 32)
	if maxDepth < 0 {
		maxDepth = 0
	}
	if maxDepth > 64 {
		maxDepth = 64
	}

	state, err := b.accessibilityState(w, maxNodes, maxDepth)
	if err != nil {
		return nil, err
	}
	return toolSuccess(state), nil
}

func (b *backend) screenshotTool(args map[string]any) (any, error) {
	w, err := b.resolveWindow(args)
	if err != nil {
		return nil, err
	}
	if err := b.focusWindow(w); err != nil {
		return nil, err
	}

	state, err := b.accessibilityState(w, 700, 64)
	if err != nil {
		return nil, err
	}
	bounds, err := b.windowRect(w, state)
	if err != nil {
		return nil, err
	}

	tmp, err := os.CreateTemp("", "cyshell-computer-use-*.png")
	if err != nil {
		return nil, err
	}
	tmpPath := tmp.Name()
	_ = tmp.Close()
	_ = os.Remove(tmpPath)
	defer os.Remove(tmpPath)

	if _, err := b.cyShellTool("desktop_capture", map[string]any{
		"target":      "current",
		"output_path": tmpPath,
	}, "capture the selected application through CyShell for ChatGPT Community"); err != nil {
		return nil, err
	}

	file, err := os.Open(tmpPath)
	if err != nil {
		return nil, fmt.Errorf("read CyShell desktop capture: %w", err)
	}
	full, err := png.Decode(file)
	_ = file.Close()
	if err != nil {
		return nil, fmt.Errorf("decode CyShell desktop capture: %w", err)
	}

	crop, actualBounds, err := cropImage(full, bounds)
	if err != nil {
		return nil, err
	}

	opts := parseShotOptions(args)
	encoded, mime, outWidth, outHeight, err := encodeShot(crop, opts)
	if err != nil {
		return nil, err
	}

	metadata := map[string]any{
		"ok":                true,
		"backend":           "cyshell",
		"cropped_to_window": true,
		"width":             outWidth,
		"height":            outHeight,
		"coordinate_width":  actualBounds.W,
		"coordinate_height": actualBounds.H,
		"scale":             float64(outWidth) / float64(maxInt(1, actualBounds.W)),
		"window_id":         w.ID,
		"window_title":      w.Title,
		"app_id":            w.AppID,
	}
	text, _ := json.Marshal(metadata)
	return map[string]any{
		"content": []map[string]any{
			{"type": "text", "text": string(text)},
			{"type": "image", "mimeType": mime, "data": base64.StdEncoding.EncodeToString(encoded)},
		},
		"structuredContent": metadata,
		"isError":           false,
	}, nil
}

func (b *backend) clickTool(args map[string]any) (any, error) {
	w, err := b.resolveWindow(args)
	if err != nil {
		return nil, err
	}
	if err := b.focusWindow(w); err != nil {
		return nil, err
	}
	x, okX := numberInt(args["x"])
	y, okY := numberInt(args["y"])
	if !okX || !okY {
		return nil, errors.New("click requires integer x and y")
	}

	if boolArg(args, "relative", false) {
		state, err := b.accessibilityState(w, 700, 64)
		if err != nil {
			return nil, err
		}
		r, err := b.windowRect(w, state)
		if err != nil {
			return nil, err
		}
		if x < 0 || y < 0 || x >= r.W || y >= r.H {
			return nil, fmt.Errorf("relative click is outside the selected window (%dx%d)", r.W, r.H)
		}
		x += r.X
		y += r.Y
	}

	button := 1
	switch strings.ToLower(stringArg(args, "button", "left")) {
	case "left", "":
		button = 1
	case "middle":
		button = 2
	case "right":
		button = 3
	default:
		return nil, errors.New("unsupported mouse button")
	}
	count := intArg(args, "click_count", 1)
	if count < 1 || count > 4 {
		return nil, errors.New("click_count must be between 1 and 4")
	}

	for i := 0; i < count; i++ {
		if _, err := b.cyShellTool("desktop_input", map[string]any{
			"action": "click",
			"target": "current",
			"x":      x,
			"y":      y,
			"button": button,
		}, "send a targeted click through CyShell for ChatGPT Community"); err != nil {
			return nil, err
		}
		if i+1 < count {
			time.Sleep(55 * time.Millisecond)
		}
	}

	return toolSuccess(map[string]any{
		"ok":        true,
		"action":    "click",
		"backend":   "cyshell",
		"window_id": w.ID,
	}), nil
}

func (b *backend) scrollTool(args map[string]any) (any, error) {
	w, err := b.resolveWindow(args)
	if err != nil {
		return nil, err
	}
	if err := b.focusWindow(w); err != nil {
		return nil, err
	}

	x, okX := numberInt(args["x"])
	y, okY := numberInt(args["y"])
	if !okX || !okY {
		return nil, errors.New("scroll requires integer x and y")
	}
	if boolArg(args, "relative", false) {
		state, err := b.accessibilityState(w, 700, 64)
		if err != nil {
			return nil, err
		}
		r, err := b.windowRect(w, state)
		if err != nil {
			return nil, err
		}
		if x < 0 || y < 0 || x >= r.W || y >= r.H {
			return nil, fmt.Errorf("relative scroll is outside the selected window (%dx%d)", r.W, r.H)
		}
		x += r.X
		y += r.Y
	}

	direction := strings.ToLower(stringArg(args, "direction", "down"))
	switch direction {
	case "up", "down", "left", "right":
	default:
		return nil, errors.New("unsupported scroll direction")
	}
	pages := floatArg(args, "pages", 1)
	if pages <= 0 {
		return nil, errors.New("pages must be positive")
	}

	if _, err := b.cyShellTool("desktop_input", map[string]any{
		"action": "mouse_move",
		"target": "current",
		"x":      x,
		"y":      y,
	}, "position the pointer through CyShell before scrolling the selected application"); err != nil {
		return nil, err
	}

	// CyShell owns focus, target resolution and permissions. Until desktop_input
	// grows a native scroll primitive, use its registered Linux input adapter as
	// an implementation detail with absolute coordinates and no window lookup.
	if _, err := b.cyShellTool("anyapp_scroll", map[string]any{
		"x":         x,
		"y":         y,
		"direction": direction,
		"pages":     pages,
		"relative":  false,
	}, "scroll the already focused application through CyShell's Linux input adapter"); err != nil {
		return nil, err
	}

	return toolSuccess(map[string]any{
		"ok":        true,
		"action":    "scroll",
		"backend":   "cyshell",
		"window_id": w.ID,
	}), nil
}

func (b *backend) pressKeyTool(args map[string]any) (any, error) {
	w, err := b.resolveWindow(args)
	if err != nil {
		return nil, err
	}
	key := strings.TrimSpace(stringArg(args, "key", ""))
	if key == "" {
		return nil, errors.New("press_key requires key")
	}
	if err := b.focusWindow(w); err != nil {
		return nil, err
	}
	if _, err := b.cyShellTool("desktop_input", map[string]any{
		"action": "key",
		"target": "current",
		"key":    key,
	}, "send a targeted key through CyShell for ChatGPT Community"); err != nil {
		return nil, err
	}
	return toolSuccess(map[string]any{"ok": true, "action": "press_key", "backend": "cyshell", "window_id": w.ID}), nil
}

func (b *backend) typeTextTool(args map[string]any) (any, error) {
	w, err := b.resolveWindow(args)
	if err != nil {
		return nil, err
	}
	text, ok := args["text"].(string)
	if !ok {
		return nil, errors.New("type_text requires text")
	}
	if err := b.focusWindow(w); err != nil {
		return nil, err
	}
	if _, err := b.cyShellTool("desktop_input", map[string]any{
		"action": "text",
		"target": "current",
		"text":   text,
	}, "type text into the selected application through CyShell for ChatGPT Community"); err != nil {
		return nil, err
	}
	return toolSuccess(map[string]any{"ok": true, "action": "type_text", "backend": "cyshell", "window_id": w.ID}), nil
}

func (b *backend) refreshWindows() ([]shellWindow, error) {
	value, err := b.cyShellTool("window_list", map[string]any{}, "list application windows through CyShell for ChatGPT Community")
	if err != nil {
		return nil, err
	}

	rawList, ok := value.([]any)
	if !ok {
		return nil, fmt.Errorf("CyShell window_list returned %T, expected a list", value)
	}

	b.mu.Lock()
	defer b.mu.Unlock()

	nextWindows := make(map[uint64]shellWindow, len(rawList))
	usedKeys := map[string]int{}
	result := make([]shellWindow, 0, len(rawList))
	for _, raw := range rawList {
		m, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		w := shellWindow{
			Index:      intArg(m, "index", -1),
			AppID:      stringArg(m, "appId", ""),
			Title:      stringArg(m, "title", ""),
			PID:        intArg(m, "pid", 0),
			Active:     boolArg(m, "active", false),
			Minimized:  boolArg(m, "minimized", false),
			Maximized:  boolArg(m, "maximized", false),
			Fullscreen: boolArg(m, "fullscreen", false),
			Screens:    stringSlice(m["screens"]),
		}
		if w.Index < 0 || (w.Title == "" && w.AppID == "") {
			continue
		}
		baseKey := w.AppID + "\x00" + w.Title
		duplicate := usedKeys[baseKey]
		usedKeys[baseKey] = duplicate + 1
		key := baseKey
		if duplicate > 0 {
			key = baseKey + "\x00" + strconv.Itoa(w.Index)
		}

		id, exists := b.idByKey[key]
		if !exists {
			id = b.nextID
			b.nextID++
			b.idByKey[key] = id
		}
		w.ID = id
		nextWindows[id] = w
		result = append(result, w)
	}

	b.windows = nextWindows
	sort.SliceStable(result, func(i, j int) bool { return result[i].Index < result[j].Index })
	return result, nil
}

func (b *backend) resolveWindow(args map[string]any) (shellWindow, error) {
	if _, err := b.refreshWindows(); err != nil {
		return shellWindow{}, err
	}

	b.mu.Lock()
	defer b.mu.Unlock()

	if raw, ok := args["window_id"]; ok {
		id, ok := numberUint64(raw)
		if !ok {
			return shellWindow{}, errors.New("invalid window_id")
		}
		if w, exists := b.windows[id]; exists {
			return w, nil
		}
		return shellWindow{}, fmt.Errorf("CyShell window %d is no longer available", id)
	}

	appID := strings.TrimSpace(stringArg(args, "app_id", ""))
	if appID != "" {
		var first *shellWindow
		for _, w := range b.windows {
			if w.AppID != appID {
				continue
			}
			candidate := w
			if candidate.Active {
				return candidate, nil
			}
			if first == nil {
				first = &candidate
			}
		}
		if first != nil {
			return *first, nil
		}
		return shellWindow{}, fmt.Errorf("CyShell app %q has no visible window", appID)
	}

	for _, w := range b.windows {
		if w.Active {
			return w, nil
		}
	}
	return shellWindow{}, errors.New("no active CyShell window is available")
}

func (b *backend) focusWindow(w shellWindow) error {
	selector := map[string]any{"index": w.Index}
	if w.Minimized {
		if _, err := b.cyShellTool("window_control", map[string]any{
			"action":   "restore",
			"selector": selector,
		}, "restore the selected application through CyShell before computer input"); err != nil {
			return fmt.Errorf("restore CyShell window: %w", err)
		}
	}
	_, err := b.cyShellTool("window_control", map[string]any{
		"action":   "focus",
		"selector": selector,
	}, "focus the selected application through CyShell before computer input")
	if err != nil {
		return fmt.Errorf("focus CyShell window: %w", err)
	}
	return nil
}

func (b *backend) accessibilityState(w shellWindow, requestedNodes int, requestedDepth int) (map[string]any, error) {
	probeNodes := requestedNodes + 160
	if probeNodes < 240 {
		probeNodes = 240
	}
	if probeNodes > 2000 {
		probeNodes = 2000
	}
	probeDepth := requestedDepth + 2
	if probeDepth < 8 {
		probeDepth = 8
	}
	if probeDepth > 64 {
		probeDepth = 64
	}

	value, err := b.cyShellTool("anyapp_get_app_state", map[string]any{
		"title":              w.Title,
		"include_screenshot": false,
		"max_nodes":          probeNodes,
		"max_depth":          probeDepth,
	}, "read the selected application's AT-SPI tree through CyShell")
	if err != nil {
		return nil, err
	}

	state, err := unwrapStructuredMap(value)
	if err != nil {
		return nil, err
	}

	state["backend"] = "cyshell-atspi"
	state["window_error"] = nil
	state["window_permissions_hint"] = nil
	state["message"] = "CyShell resolved the target window and AT-SPI supplied application semantics."

	readiness, _ := state["readiness"].(map[string]any)
	if readiness == nil {
		readiness = map[string]any{}
	}
	readiness["blockers"] = []any{}
	readiness["can_query_windows"] = true
	readiness["can_focus_windows"] = true
	readiness["can_focus_apps"] = true
	readiness["can_build_accessibility_tree"] = true
	readiness["recommended_next_step"] = "Use CyShell window targeting."
	state["readiness"] = readiness

	filtered := filterAccessibilityTree(state["accessibility_tree"], w.Title, requestedNodes)
	if filtered != nil {
		state["accessibility_tree"] = filtered
		state["accessibility_tree_raw_count"] = len(filtered)
	}

	context := map[string]any{
		"window_id":  w.ID,
		"index":      w.Index,
		"title":      w.Title,
		"app_id":     w.AppID,
		"pid":        w.PID,
		"focused":    w.Active,
		"minimized":  w.Minimized,
		"maximized":  w.Maximized,
		"fullscreen": w.Fullscreen,
		"screens":    w.Screens,
		"backend":    "cyshell",
	}
	if r, err := b.windowRectFromState(w, state); err == nil {
		context["bounds"] = map[string]any{"x": r.X, "y": r.Y, "width": r.W, "height": r.H}
	}
	state["window_context"] = context
	return state, nil
}

func filterAccessibilityTree(raw any, title string, limit int) []any {
	tree, ok := raw.([]any)
	if !ok || len(tree) == 0 {
		return nil
	}

	targetIndex := -1
	parentByIndex := map[int]int{}
	for _, item := range tree {
		node, ok := item.(map[string]any)
		if !ok {
			continue
		}
		idx := intArg(node, "index", -1)
		parent := intArg(node, "parent_index", -1)
		if idx >= 0 {
			parentByIndex[idx] = parent
		}
		if strings.EqualFold(stringArg(node, "role", ""), "frame") && stringArg(node, "name", "") == title {
			targetIndex = idx
		}
	}
	if targetIndex < 0 {
		if limit > 0 && len(tree) > limit {
			return append([]any(nil), tree[:limit]...)
		}
		return tree
	}

	include := map[int]bool{targetIndex: true}
	for idx := targetIndex; idx >= 0; {
		parent, ok := parentByIndex[idx]
		if !ok || parent < 0 {
			break
		}
		include[parent] = true
		idx = parent
	}

	changed := true
	for changed {
		changed = false
		for _, item := range tree {
			node, ok := item.(map[string]any)
			if !ok {
				continue
			}
			idx := intArg(node, "index", -1)
			parent := intArg(node, "parent_index", -1)
			if idx >= 0 && parent >= 0 && include[parent] && !include[idx] {
				include[idx] = true
				changed = true
			}
		}
	}

	out := make([]any, 0, len(include))
	for _, item := range tree {
		node, ok := item.(map[string]any)
		if !ok {
			continue
		}
		idx := intArg(node, "index", -1)
		if include[idx] {
			out = append(out, item)
			if limit > 0 && len(out) >= limit {
				break
			}
		}
	}
	return out
}

func (b *backend) windowRect(w shellWindow, state map[string]any) (rect, error) {
	r, err := b.windowRectFromState(w, state)
	if err != nil {
		return rect{}, err
	}
	if !r.valid() {
		return rect{}, errors.New("CyShell could not determine a usable target window rectangle")
	}
	return r, nil
}

func (b *backend) windowRectFromState(w shellWindow, state map[string]any) (rect, error) {
	raw, ok := frameBounds(state["accessibility_tree"], w.Title)
	if !ok {
		return rect{}, fmt.Errorf("AT-SPI did not expose frame bounds for %q", w.Title)
	}
	outputs, err := b.outputLayout()
	if err != nil {
		return raw, nil
	}
	if len(w.Screens) == 0 {
		return raw, nil
	}
	output, ok := outputs[w.Screens[0]]
	if !ok || !output.valid() {
		return raw, nil
	}
	return normalizeWindowRect(raw, output), nil
}

func frameBounds(raw any, title string) (rect, bool) {
	tree, ok := raw.([]any)
	if !ok {
		return rect{}, false
	}
	for _, item := range tree {
		node, ok := item.(map[string]any)
		if !ok {
			continue
		}
		if !strings.EqualFold(stringArg(node, "role", ""), "frame") || stringArg(node, "name", "") != title {
			continue
		}
		bounds, ok := node["bounds"].(map[string]any)
		if !ok {
			continue
		}
		x, okX := numberInt(bounds["x"])
		y, okY := numberInt(bounds["y"])
		w, okW := numberInt(bounds["width"])
		h, okH := numberInt(bounds["height"])
		if okX && okY && okW && okH && w > 0 && h > 0 {
			return rect{X: x, Y: y, W: w, H: h}, true
		}
	}
	return rect{}, false
}

func normalizeWindowRect(raw rect, out outputGeometry) rect {
	centerX := raw.X + raw.W/2
	centerY := raw.Y + raw.H/2
	if centerX >= out.X && centerX < out.X+out.Width && centerY >= out.Y && centerY < out.Y+out.Height {
		return raw
	}

	localCenterX := raw.X + raw.W/2
	localCenterY := raw.Y + raw.H/2
	if localCenterX >= 0 && localCenterX < out.Width && localCenterY >= 0 && localCenterY < out.Height {
		translated := raw
		translated.X += out.X
		translated.Y += out.Y
		return translated
	}
	return raw
}

func (b *backend) outputLayout() (map[string]outputGeometry, error) {
	value, err := b.cyShellTool("shell_settings_get", map[string]any{
		"key": "labwcDisplayConfiguration",
	}, "read CyShell display layout to normalize application coordinates")
	if err != nil {
		return nil, err
	}
	root, ok := value.(map[string]any)
	if !ok {
		return nil, errors.New("CyShell display configuration is not an object")
	}
	config, _ := root["value"].(map[string]any)
	outputsRaw, _ := config["outputs"].(map[string]any)
	if outputsRaw == nil {
		return nil, errors.New("CyShell display configuration has no outputs")
	}

	outputs := map[string]outputGeometry{}
	for name, raw := range outputsRaw {
		item, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		pos, _ := item["position"].(map[string]any)
		mode, _ := item["mode"].(map[string]any)
		output := outputGeometry{
			Name:   name,
			X:      intArg(pos, "x", 0),
			Y:      intArg(pos, "y", 0),
			Width:  intArg(mode, "width", 0),
			Height: intArg(mode, "height", 0),
			Scale:  floatArg(item, "scale", 1),
		}
		if output.Scale <= 0 {
			output.Scale = 1
		}
		outputs[name] = output
	}
	return outputs, nil
}

type shotOptions struct {
	MaxWidth  int
	MaxHeight int
	MaxBytes  int
	Scale     float64
	Format    string
	Quality   int
}

func parseShotOptions(args map[string]any) shotOptions {
	opts := shotOptions{
		MaxWidth:  intArg(args, "max_width", 0),
		MaxHeight: intArg(args, "max_height", 0),
		MaxBytes:  intArg(args, "max_bytes", 0),
		Scale:     floatArg(args, "scale", 1),
		Format:    strings.ToLower(stringArg(args, "format", "png")),
		Quality:   intArg(args, "quality", 85),
	}
	if opts.Scale <= 0 || opts.Scale > 1 {
		opts.Scale = 1
	}
	if opts.Format != "jpeg" && opts.Format != "png" {
		opts.Format = "png"
	}
	if opts.Quality < 1 || opts.Quality > 95 {
		opts.Quality = 85
	}
	return opts
}

func cropImage(src image.Image, requested rect) (image.Image, rect, error) {
	bounds := src.Bounds()
	x0 := maxInt(bounds.Min.X, requested.X)
	y0 := maxInt(bounds.Min.Y, requested.Y)
	x1 := minInt(bounds.Max.X, requested.X+requested.W)
	y1 := minInt(bounds.Max.Y, requested.Y+requested.H)
	if x1 <= x0 || y1 <= y0 {
		return nil, rect{}, fmt.Errorf("target window rectangle %+v does not intersect the CyShell desktop capture %v", requested, bounds)
	}
	actual := rect{X: x0, Y: y0, W: x1 - x0, H: y1 - y0}
	dst := image.NewRGBA(image.Rect(0, 0, actual.W, actual.H))
	draw.Draw(dst, dst.Bounds(), src, image.Point{X: x0, Y: y0}, draw.Src)
	return dst, actual, nil
}

func encodeShot(src image.Image, opts shotOptions) ([]byte, string, int, int, error) {
	sourceBounds := src.Bounds()
	sourceW := sourceBounds.Dx()
	sourceH := sourceBounds.Dy()
	if sourceW <= 0 || sourceH <= 0 {
		return nil, "", 0, 0, errors.New("empty screenshot crop")
	}

	scale := opts.Scale
	if scale <= 0 || scale > 1 {
		scale = 1
	}
	if opts.MaxWidth > 0 && float64(sourceW)*scale > float64(opts.MaxWidth) {
		scale = math.Min(scale, float64(opts.MaxWidth)/float64(sourceW))
	}
	if opts.MaxHeight > 0 && float64(sourceH)*scale > float64(opts.MaxHeight) {
		scale = math.Min(scale, float64(opts.MaxHeight)/float64(sourceH))
	}
	if scale <= 0 {
		scale = 1
	}

	width := maxInt(1, int(math.Round(float64(sourceW)*scale)))
	height := maxInt(1, int(math.Round(float64(sourceH)*scale)))
	current := resizeImage(src, width, height)

	encode := func(img image.Image) ([]byte, string, error) {
		var buf bytes.Buffer
		if opts.Format == "jpeg" {
			if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: opts.Quality}); err != nil {
				return nil, "", err
			}
			return buf.Bytes(), "image/jpeg", nil
		}
		enc := png.Encoder{CompressionLevel: png.BestSpeed}
		if err := enc.Encode(&buf, img); err != nil {
			return nil, "", err
		}
		return buf.Bytes(), "image/png", nil
	}

	data, mime, err := encode(current)
	if err != nil {
		return nil, "", 0, 0, err
	}
	for opts.MaxBytes > 0 && len(data) > opts.MaxBytes && width > 1 && height > 1 {
		factor := math.Sqrt(float64(opts.MaxBytes)/float64(len(data))) * 0.92
		if factor > 0.92 {
			factor = 0.92
		}
		if factor < 0.25 {
			factor = 0.25
		}
		nextW := maxInt(1, int(float64(width)*factor))
		nextH := maxInt(1, int(float64(height)*factor))
		if nextW == width && width > 1 {
			nextW--
		}
		if nextH == height && height > 1 {
			nextH--
		}
		width, height = nextW, nextH
		current = resizeImage(current, width, height)
		data, mime, err = encode(current)
		if err != nil {
			return nil, "", 0, 0, err
		}
	}
	if opts.MaxBytes > 0 && len(data) > opts.MaxBytes {
		return nil, "", 0, 0, fmt.Errorf("unable to fit screenshot under max_bytes=%d", opts.MaxBytes)
	}
	return data, mime, width, height, nil
}

func resizeImage(src image.Image, width, height int) image.Image {
	if src.Bounds().Dx() == width && src.Bounds().Dy() == height {
		return src
	}
	dst := image.NewRGBA(image.Rect(0, 0, width, height))
	xdraw.CatmullRom.Scale(dst, dst.Bounds(), src, src.Bounds(), xdraw.Over, nil)
	return dst
}

func (b *backend) cyShellTool(name string, arguments map[string]any, reason string) (any, error) {
	if arguments == nil {
		arguments = map[string]any{}
	}
	arguments["reason"] = reason
	value, err := b.call("cycom.tools.call", map[string]any{
		"name":      name,
		"reason":    reason,
		"arguments": arguments,
		"origin": map[string]any{
			"kind":    "mcp",
			"name":    "ChatGPT Community / CyShell Computer Use",
			"version": "1",
		},
	})
	if err != nil {
		return nil, err
	}
	if m, ok := value.(map[string]any); ok {
		if isError, _ := m["isError"].(bool); isError {
			return nil, errors.New(toolResultText(m))
		}
	}
	return value, nil
}

func unwrapStructuredMap(value any) (map[string]any, error) {
	m, ok := value.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("accessibility result has type %T", value)
	}
	for _, key := range []string{"structured", "structuredContent"} {
		if structured, ok := m[key].(map[string]any); ok {
			return cloneMap(structured), nil
		}
	}
	if _, exists := m["accessibility_tree"]; exists {
		return cloneMap(m), nil
	}

	content, _ := m["content"].([]any)
	for _, item := range content {
		entry, _ := item.(map[string]any)
		if entry == nil || entry["type"] != "text" {
			continue
		}
		text, _ := entry["text"].(string)
		var parsed map[string]any
		dec := json.NewDecoder(strings.NewReader(text))
		dec.UseNumber()
		if dec.Decode(&parsed) == nil {
			return parsed, nil
		}
	}
	return nil, errors.New("CyShell accessibility adapter returned no structured state")
}

func cloneMap(input map[string]any) map[string]any {
	encoded, _ := json.Marshal(input)
	var out map[string]any
	dec := json.NewDecoder(bytes.NewReader(encoded))
	dec.UseNumber()
	_ = dec.Decode(&out)
	if out == nil {
		out = map[string]any{}
	}
	return out
}

func toolResultText(m map[string]any) string {
	content, _ := m["content"].([]any)
	var parts []string
	for _, item := range content {
		entry, _ := item.(map[string]any)
		if entry == nil {
			continue
		}
		if text, _ := entry["text"].(string); text != "" {
			parts = append(parts, text)
		}
	}
	if len(parts) == 0 {
		return "CyShell tool call failed"
	}
	return strings.Join(parts, "\n")
}

func toolSuccess(data any) map[string]any {
	encoded, _ := json.Marshal(data)
	return map[string]any{
		"content":           []map[string]any{{"type": "text", "text": string(encoded)}},
		"structuredContent": data,
		"isError":           false,
	}
}

func toolError(err error) map[string]any {
	return map[string]any{
		"content": []map[string]any{{"type": "text", "text": err.Error()}},
		"isError": true,
	}
}

func rpcErrorResponse(id json.RawMessage, code int, message string, data any) map[string]any {
	response := map[string]any{
		"jsonrpc": "2.0",
		"error": map[string]any{
			"code":    code,
			"message": message,
		},
	}
	if id != nil {
		response["id"] = json.RawMessage(id)
	}
	if data != nil {
		response["error"].(map[string]any)["data"] = data
	}
	return response
}

func decodeMap(raw json.RawMessage) (map[string]any, error) {
	if len(raw) == 0 || string(raw) == "null" {
		return map[string]any{}, nil
	}
	var out map[string]any
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	if err := dec.Decode(&out); err != nil {
		return nil, err
	}
	return out, nil
}

func rawString(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var value string
	_ = json.Unmarshal(raw, &value)
	return value
}

func stringArg(m map[string]any, key, fallback string) string {
	if m == nil {
		return fallback
	}
	value, ok := m[key].(string)
	if !ok {
		return fallback
	}
	return value
}

func boolArg(m map[string]any, key string, fallback bool) bool {
	if m == nil {
		return fallback
	}
	value, ok := m[key].(bool)
	if !ok {
		return fallback
	}
	return value
}

func intArg(m map[string]any, key string, fallback int) int {
	if m == nil {
		return fallback
	}
	if value, ok := numberInt(m[key]); ok {
		return value
	}
	return fallback
}

func floatArg(m map[string]any, key string, fallback float64) float64 {
	if m == nil {
		return fallback
	}
	switch value := m[key].(type) {
	case float64:
		return value
	case float32:
		return float64(value)
	case int:
		return float64(value)
	case int64:
		return float64(value)
	case json.Number:
		if parsed, err := value.Float64(); err == nil {
			return parsed
		}
	}
	return fallback
}

func numberInt(value any) (int, bool) {
	switch n := value.(type) {
	case int:
		return n, true
	case int64:
		return int(n), true
	case uint64:
		if n <= uint64(^uint(0)>>1) {
			return int(n), true
		}
	case float64:
		if math.Trunc(n) == n && n >= float64(math.MinInt) && n <= float64(math.MaxInt) {
			return int(n), true
		}
	case json.Number:
		if parsed, err := n.Int64(); err == nil {
			return int(parsed), true
		}
	}
	return 0, false
}

func numberUint64(value any) (uint64, bool) {
	switch n := value.(type) {
	case uint64:
		return n, true
	case uint:
		return uint64(n), true
	case int:
		if n >= 0 {
			return uint64(n), true
		}
	case int64:
		if n >= 0 {
			return uint64(n), true
		}
	case float64:
		if n >= 0 && math.Trunc(n) == n && n <= float64(1<<53-1) {
			return uint64(n), true
		}
	case json.Number:
		if parsed, err := strconv.ParseUint(n.String(), 10, 64); err == nil {
			return parsed, true
		}
	case string:
		if parsed, err := strconv.ParseUint(n, 10, 64); err == nil {
			return parsed, true
		}
	}
	return 0, false
}

func stringSlice(value any) []string {
	switch list := value.(type) {
	case []string:
		return append([]string(nil), list...)
	case []any:
		out := make([]string, 0, len(list))
		for _, item := range list {
			if text, ok := item.(string); ok {
				out = append(out, text)
			}
		}
		return out
	default:
		return nil
	}
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
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
	request := map[string]any{"id": 1, "method": method, "params": params}
	if err := json.NewEncoder(conn).Encode(request); err != nil {
		return nil, err
	}
	if !scanner.Scan() {
		if err := scanner.Err(); err != nil {
			return nil, err
		}
		return nil, errors.New("CyShell core closed the IPC connection")
	}

	var response map[string]json.RawMessage
	if err := json.Unmarshal(scanner.Bytes(), &response); err != nil {
		return nil, fmt.Errorf("decode CyShell IPC response: %w", err)
	}
	if raw := response["error"]; len(raw) > 0 && string(raw) != "null" && string(raw) != "\"\"" {
		var text string
		if json.Unmarshal(raw, &text) == nil && text != "" {
			return nil, errors.New(text)
		}
		return nil, fmt.Errorf("CyShell IPC error: %s", string(raw))
	}
	raw := response["result"]
	if len(raw) == 0 || string(raw) == "null" {
		return nil, nil
	}
	var value any
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	if err := dec.Decode(&value); err != nil {
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
