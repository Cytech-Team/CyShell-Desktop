package main

import (
	"encoding/json"
	"image"
	"image/color"
	"testing"
)

func TestNormalizeWindowRect(t *testing.T) {
	out := outputGeometry{Name: "HDMI-A-1", X: 1920, Y: 0, Width: 2560, Height: 1440, Scale: 1}

	local := rect{X: 0, Y: 0, W: 1288, H: 1402}
	got := normalizeWindowRect(local, out)
	want := rect{X: 1920, Y: 0, W: 1288, H: 1402}
	if got != want {
		t.Fatalf("local bounds: got %+v want %+v", got, want)
	}

	global := rect{X: 2200, Y: 20, W: 1200, H: 1000}
	got = normalizeWindowRect(global, out)
	if got != global {
		t.Fatalf("global bounds changed: got %+v want %+v", got, global)
	}
}

func TestFilterAccessibilityTree(t *testing.T) {
	tree := []any{
		map[string]any{"index": 0, "parent_index": nil, "role": "application", "name": "Other"},
		map[string]any{"index": 1, "parent_index": nil, "role": "application", "name": "Brave Browser"},
		map[string]any{"index": 2, "parent_index": 1, "role": "frame", "name": "Target - Brave"},
		map[string]any{"index": 3, "parent_index": 2, "role": "panel", "name": "Toolbar"},
		map[string]any{"index": 4, "parent_index": 3, "role": "entry", "name": "Address"},
		map[string]any{"index": 5, "parent_index": nil, "role": "application", "name": "Another"},
	}

	filtered := filterAccessibilityTree(tree, "Target - Brave", 20)
	if len(filtered) != 4 {
		t.Fatalf("filtered nodes=%d want 4: %#v", len(filtered), filtered)
	}
	for _, raw := range filtered {
		node := raw.(map[string]any)
		if intArg(node, "index", -1) == 0 || intArg(node, "index", -1) == 5 {
			t.Fatalf("unrelated node leaked into filtered tree: %#v", node)
		}
	}
}

func TestWindowListUsesStableCyShellIDs(t *testing.T) {
	fake := func(method string, params map[string]any) (any, error) {
		if method != "cycom.tools.call" {
			t.Fatalf("unexpected IPC method %q", method)
		}
		if params["name"] != "window_list" {
			t.Fatalf("unexpected tool %v", params["name"])
		}
		return []any{
			map[string]any{
				"index": 0, "appId": "codex-desktop", "title": "ChatGPT",
				"active": false, "screens": []any{"eDP-1"},
			},
			map[string]any{
				"index": 1, "appId": "brave-browser", "title": "Target - Brave",
				"active": true, "screens": []any{"HDMI-A-1"},
			},
		}, nil
	}

	b := newBackend(fake)
	first, err := b.refreshWindows()
	if err != nil {
		t.Fatal(err)
	}
	second, err := b.refreshWindows()
	if err != nil {
		t.Fatal(err)
	}
	if len(first) != 2 || len(second) != 2 {
		t.Fatalf("unexpected window counts first=%d second=%d", len(first), len(second))
	}
	if first[0].ID == 0 || first[1].ID == 0 {
		t.Fatal("window ids must be non-zero")
	}
	if first[0].ID != second[0].ID || first[1].ID != second[1].ID {
		t.Fatalf("window ids changed across refresh: first=%v second=%v", first, second)
	}
}

func TestAccessibilityStateReplacesBrokenWindowBackend(t *testing.T) {
	fake := func(method string, params map[string]any) (any, error) {
		if method != "cycom.tools.call" {
			t.Fatalf("unexpected IPC method %q", method)
		}
		switch params["name"] {
		case "anyapp_get_app_state":
			return map[string]any{
				"isError": false,
				"structured": map[string]any{
					"backend":      "linux-atspi",
					"window_error": "unsupported compositor",
					"readiness": map[string]any{
						"can_query_windows": false,
						"blockers":          []any{"window backend unavailable"},
					},
					"accessibility_tree": []any{
						map[string]any{
							"index": 0, "parent_index": nil, "role": "application", "name": "Brave Browser",
						},
						map[string]any{
							"index": 1, "parent_index": 0, "role": "frame", "name": "Target - Brave",
							"bounds": map[string]any{"x": 0, "y": 0, "width": 1288, "height": 1402},
						},
						map[string]any{
							"index": 2, "parent_index": 1, "role": "entry", "name": "Address",
						},
					},
				},
			}, nil
		case "shell_settings_get":
			return map[string]any{
				"key": "labwcDisplayConfiguration",
				"value": map[string]any{
					"outputs": map[string]any{
						"HDMI-A-1": map[string]any{
							"position": map[string]any{"x": 1920, "y": 0},
							"mode":     map[string]any{"width": 2560, "height": 1440},
							"scale":    1,
						},
					},
				},
			}, nil
		default:
			t.Fatalf("unexpected tool %v", params["name"])
			return nil, nil
		}
	}

	b := newBackend(fake)
	w := shellWindow{ID: 7, Index: 1, AppID: "brave-browser", Title: "Target - Brave", Screens: []string{"HDMI-A-1"}}
	state, err := b.accessibilityState(w, 80, 16)
	if err != nil {
		t.Fatal(err)
	}
	if state["window_error"] != nil {
		t.Fatalf("window_error not cleared: %#v", state["window_error"])
	}
	if state["backend"] != "cyshell-atspi" {
		t.Fatalf("backend=%v", state["backend"])
	}
	context, ok := state["window_context"].(map[string]any)
	if !ok {
		t.Fatalf("missing window_context: %#v", state["window_context"])
	}
	bounds, ok := context["bounds"].(map[string]any)
	if !ok {
		t.Fatalf("missing normalized bounds: %#v", context)
	}
	if intArg(bounds, "x", -1) != 1920 || intArg(bounds, "width", 0) != 1288 {
		t.Fatalf("unexpected normalized bounds: %#v", bounds)
	}
	readiness := state["readiness"].(map[string]any)
	if readiness["can_query_windows"] != true || readiness["can_focus_windows"] != true {
		t.Fatalf("CyShell readiness not patched: %#v", readiness)
	}
}

func TestCropAndEncodeShot(t *testing.T) {
	src := image.NewRGBA(image.Rect(0, 0, 400, 300))
	for y := 0; y < 300; y++ {
		for x := 0; x < 400; x++ {
			src.Set(x, y, color.RGBA{R: uint8(x), G: uint8(y), B: 90, A: 255})
		}
	}
	crop, bounds, err := cropImage(src, rect{X: 100, Y: 50, W: 200, H: 100})
	if err != nil {
		t.Fatal(err)
	}
	if bounds != (rect{X: 100, Y: 50, W: 200, H: 100}) {
		t.Fatalf("bounds=%+v", bounds)
	}
	data, mime, width, height, err := encodeShot(crop, shotOptions{MaxWidth: 100, Scale: 1, Format: "jpeg", Quality: 70})
	if err != nil {
		t.Fatal(err)
	}
	if mime != "image/jpeg" || width != 100 || height != 50 || len(data) == 0 {
		t.Fatalf("encoded shot mime=%s size=%dx%d bytes=%d", mime, width, height, len(data))
	}
}

func TestMCPListWindowsContract(t *testing.T) {
	fake := func(method string, params map[string]any) (any, error) {
		if params["name"] == "window_list" {
			return []any{
				map[string]any{"index": 0, "appId": "codex-desktop", "title": "ChatGPT", "active": true, "screens": []any{"eDP-1"}},
			}, nil
		}
		return nil, nil
	}
	b := newBackend(fake)

	params, _ := json.Marshal(map[string]any{"name": "list_windows", "arguments": map[string]any{}})
	result, rpcErr := b.dispatch("tools/call", params)
	if rpcErr != nil {
		t.Fatalf("rpc error: %#v", rpcErr)
	}
	toolResult := result.(map[string]any)
	if toolResult["isError"] != false {
		t.Fatalf("unexpected tool error: %#v", toolResult)
	}
	structured := toolResult["structuredContent"].(map[string]any)
	windows := structured["windows"].([]map[string]any)
	if len(windows) != 1 || windows[0]["backend"] != "cyshell" {
		t.Fatalf("unexpected list_windows result: %#v", structured)
	}
}
