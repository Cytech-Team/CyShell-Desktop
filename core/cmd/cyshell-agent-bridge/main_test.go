package main

import "testing"

func TestCapabilitySet(t *testing.T) {
	caps := capabilitySet(map[string]any{
		"capabilities": []any{"network", "bluetooth", 123},
	})
	if !caps["network"] || !caps["bluetooth"] || caps["brightness"] {
		t.Fatalf("unexpected capability set: %#v", caps)
	}
}
