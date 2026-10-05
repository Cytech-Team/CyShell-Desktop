package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const shellDirName = "cyshell"

// LocateCyShellConfig returns the first directory containing shell.qml.
// CyShell paths are authoritative. The old quickshell/dms locations are read
// only as a migration fallback so existing installs can still start.
func LocateCyShellConfig() (string, error) {
	var primaryPaths []string
	var legacyPaths []string

	if explicit := strings.TrimSpace(os.Getenv("CYSHELL_SHELL_DIR")); explicit != "" {
		primaryPaths = append(primaryPaths, explicit)
	} else if legacy := strings.TrimSpace(os.Getenv("CyShell_SHELL_DIR")); legacy != "" {
		legacyPaths = append(legacyPaths, legacy)
	}

	configHome, err := os.UserConfigDir()
	if err == nil && configHome != "" {
		primaryPaths = append(primaryPaths, filepath.Join(configHome, "quickshell", shellDirName))
		legacyPaths = append(legacyPaths, filepath.Join(configHome, "quickshell", "dms"))
	}

	dataDirs := os.Getenv("XDG_DATA_DIRS")
	if dataDirs == "" {
		dataDirs = "/usr/local/share:/usr/share"
	}
	for dir := range strings.SplitSeq(dataDirs, ":") {
		if dir == "" {
			continue
		}
		primaryPaths = append(primaryPaths, filepath.Join(dir, "quickshell", shellDirName))
		legacyPaths = append(legacyPaths, filepath.Join(dir, "quickshell", "dms"))
	}

	configDirs := os.Getenv("XDG_CONFIG_DIRS")
	if configDirs == "" {
		configDirs = "/etc/xdg"
	}
	for dir := range strings.SplitSeq(configDirs, ":") {
		if dir == "" {
			continue
		}
		primaryPaths = append(primaryPaths, filepath.Join(dir, "quickshell", shellDirName))
		legacyPaths = append(legacyPaths, filepath.Join(dir, "quickshell", "dms"))
	}

	search := func(paths []string) string {
		for _, base := range paths {
			candidates := []string{base, filepath.Join(base, "quickshell")}
			for _, candidate := range candidates {
				shellPath := filepath.Join(candidate, "shell.qml")
				if info, err := os.Stat(shellPath); err == nil && !info.IsDir() {
					return candidate
				}
			}
		}
		return ""
	}

	if path := search(primaryPaths); path != "" {
		return path, nil
	}
	if path := search(legacyPaths); path != "" {
		return path, nil
	}
	return "", fmt.Errorf("could not find CyShell config (shell.qml) in any valid config path")
}
