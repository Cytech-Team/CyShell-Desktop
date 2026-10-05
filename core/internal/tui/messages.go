package tui

import (
	"github.com/Cytech-Team/CyShell-Desktop/core/internal/deps"
	"github.com/Cytech-Team/CyShell-Desktop/core/internal/distros"
)

type logMsg struct {
	message string
}

type osInfoCompleteMsg struct {
	info *distros.OSInfo
	err  error
}

type depsDetectedMsg struct {
	deps []deps.Dependency
	err  error
}

type packageInstallProgressMsg struct {
	progress    float64
	step        string
	isComplete  bool
	needsSudo   bool
	commandInfo string
	logOutput   string
	error       error
}

type packageProgressCompletedMsg struct{}

type passwordValidMsg struct {
	password string
	valid    bool
}

type delayCompleteMsg struct{}
