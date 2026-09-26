package cycom

import "testing"

func TestRankSemanticNodesPrefersExactNameAndCapsResults(t *testing.T) {
	nodes := []any{
		map[string]any{"id": "settings:display", "role": "settings-page", "name": "Display settings"},
		map[string]any{"id": "surface:settings", "role": "surface", "name": "Settings"},
		map[string]any{"id": "settings:appearance", "role": "settings-page", "name": "Appearance settings"},
	}
	got := rankSemanticNodes(nodes, "settings", 2)
	if len(got) != 2 {
		t.Fatalf("len = %d, want 2: %#v", len(got), got)
	}
	first := got[0].(map[string]any)
	if first["id"] != "surface:settings" {
		t.Fatalf("exact semantic name should rank first: %#v", got)
	}
}

func TestRankSemanticNodesMatchesMultipleTermsAcrossFields(t *testing.T) {
	nodes := []any{
		map[string]any{"id": "window:1", "role": "window", "name": "ChatGPT", "appId": "com.openai.chat"},
		map[string]any{"id": "window:2", "role": "window", "name": "Browser", "appId": "com.browser"},
	}
	got := rankSemanticNodes(nodes, "chat openai", 10)
	if len(got) != 1 || got[0].(map[string]any)["id"] != "window:1" {
		t.Fatalf("unexpected multi-term ranking: %#v", got)
	}
}

func TestRankSemanticNodesPreservesOrderForEmptyQuery(t *testing.T) {
	nodes := []any{
		map[string]any{"id": "first"},
		map[string]any{"id": "second"},
		map[string]any{"id": "third"},
	}
	got := rankSemanticNodes(nodes, "", 2)
	if len(got) != 2 || got[0].(map[string]any)["id"] != "first" || got[1].(map[string]any)["id"] != "second" {
		t.Fatalf("empty query should preserve semantic source order: %#v", got)
	}
}
