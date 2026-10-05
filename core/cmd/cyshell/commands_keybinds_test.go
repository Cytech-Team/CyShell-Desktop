package main

import (
	"errors"
	"testing"
)

func TestKeybindEditFailure(t *testing.T) {
	err := errors.New("transport failed")
	result := keybindEditFailure(err)
	if result["success"] != false || result["code"] != "command_failed" || result["message"] != err.Error() {
		t.Fatalf("unexpected failure result: %#v", result)
	}
}
