package main

import (
	"os"
	"runtime"
	"strings"
)

func disableMemProfilingUnlessRequested() {
	if os.Getenv("CYSHELL_PPROF") != "" {
		return
	}
	runtime.MemProfileRate = 0
}

// isReadOnlyCommand returns true if the CLI args indicate a command that is
// safe to run as root (e.g. shell completion, help).
func isReadOnlyCommand(args []string) bool {
	for _, arg := range args[1:] {
		if strings.HasPrefix(arg, "-") {
			continue
		}
		switch arg {
		case "completion", "help", "__complete", "system":
			return true
		}
		return false
	}
	return false
}

