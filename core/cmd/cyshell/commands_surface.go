package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/spf13/cobra"
)

type surfaceSpec struct {
	Entrypoint string
	Role       string
	Unit       string
}

var surfaceSpecs = map[string]surfaceSpec{
	"runtime":  {Entrypoint: "runtime.qml", Role: "runtime", Unit: "cyshell-runtime-ui.service"},
	"shell":    {Entrypoint: "ui.qml", Role: "shell", Unit: "cyshell-shell-ui.service"},
	"settings": {Entrypoint: "settings.qml", Role: "settings", Unit: "cyshell-settings-surface.service"},
	"panel":    {Entrypoint: "panel.qml", Role: "panel", Unit: "cyshell-panel.service"},
	"desktop":  {Entrypoint: "desktop.qml", Role: "desktop", Unit: "cyshell-desktop.service"},
	"osd":      {Entrypoint: "osd.qml", Role: "osd", Unit: "cyshell-osd.service"},
	"surfaces": {Entrypoint: "surfaces.qml", Role: "surfaces", Unit: "cyshell-ui-surfaces.service"},
}

var surfaceCmd = &cobra.Command{
	Use:   "surface [role]",
	Short: "Run or manage an isolated CyShell UI role",
	Long: "Run or manage one isolated CyShell UI role. Direct role execution is used by systemd; " +
		"use restart/status/list for operator control.",
	Args: cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		if len(args) == 0 {
			return cmd.Help()
		}
		return runSurface(cmd, args[0])
	},
}

var surfaceRestartCmd = &cobra.Command{
	Use:   "restart <role>",
	Short: "Restart exactly one CyShell UI role",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		spec, ok := surfaceSpecs[args[0]]
		if !ok {
			return unknownSurface(args[0])
		}
		if err := runUserUnit("restart", spec.Unit); err != nil {
			return err
		}
		fmt.Printf("%s restarted\n", args[0])
		return nil
	},
}

var surfaceRefreshCmd = &cobra.Command{
	Use:     "refresh <role>",
	Aliases: []string{"reload"},
	Short:   "Refresh one CyShell UI role in place without restarting its service",
	Args:    cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		role := args[0]
		targets := map[string]string{
			"shell":    "shell-ui",
			"settings": "settings",
			"panel":    "panel",
			"desktop":  "desktop",
			"osd":      "osd",
			"surfaces": "surfaces",
		}
		target, ok := targets[role]
		if !ok {
			if _, exists := surfaceSpecs[role]; !exists {
				return unknownSurface(role)
			}
			return fmt.Errorf("surface %q has no in-place refresh contract; use restart instead", role)
		}
		result, err := callSurfaceIPC(role, target, "refresh", nil)
		if err != nil {
			return err
		}
		if result != "" {
			fmt.Println(result)
		}
		return nil
	},
}

var surfaceStatusCmd = &cobra.Command{
	Use:   "status [role]",
	Short: "Show CyShell UI role status",
	Args:  cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		if len(args) == 1 {
			return printSurfaceStatus(args[0])
		}
		for _, role := range surfaceRoleNames() {
			if err := printSurfaceStatus(role); err != nil {
				return err
			}
		}
		return nil
	},
}

var surfaceListCmd = &cobra.Command{
	Use:   "list",
	Short: "List isolated CyShell UI roles",
	Run: func(cmd *cobra.Command, args []string) {
		for _, role := range surfaceRoleNames() {
			spec := surfaceSpecs[role]
			fmt.Printf("%-9s %-34s %s\n", role, spec.Unit, spec.Entrypoint)
		}
	},
}

var settingsCmd = &cobra.Command{
	Use:   "settings [ipc-method] [args...]",
	Short: "Open or control the independent Settings window",
	Long: "Open or control the independent CyShell Settings surface.\n\n" +
		"With no method, Settings is opened. Advanced callers may pass the Settings\n" +
		"IPC method directly, for example:\n\n" +
		"  cyshell settings open\n" +
		"  cyshell settings openWithTab agent\n" +
		"  cyshell settings focusOrToggle",
	Args: cobra.ArbitraryArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		method := "open"
		var methodArgs []string
		if len(args) > 0 {
			method = args[0]
			methodArgs = args[1:]
		}
		return callSettingsIPC(cmd, method, methodArgs)
	},
}

func init() {
	surfaceCmd.AddCommand(surfaceRestartCmd, surfaceRefreshCmd, surfaceStatusCmd, surfaceListCmd)
}

func surfaceRoleNames() []string {
	roles := make([]string, 0, len(surfaceSpecs))
	for role := range surfaceSpecs {
		roles = append(roles, role)
	}
	sort.Strings(roles)
	return roles
}

func unknownSurface(name string) error {
	return fmt.Errorf("unknown surface %q (available: %s)", name, strings.Join(surfaceRoleNames(), ", "))
}

func runSurface(cmd *cobra.Command, name string) error {
	spec, ok := surfaceSpecs[name]
	if !ok {
		return unknownSurface(name)
	}

	if err := shellApp.ResolveConfig(cmd, nil); err != nil {
		return err
	}
	configPath := shellApp.ConfigPath()
	entryPath := filepath.Join(configPath, spec.Entrypoint)
	if info, err := os.Stat(entryPath); err != nil {
		return fmt.Errorf("surface entrypoint %s: %w", entryPath, err)
	} else if info.IsDir() {
		return fmt.Errorf("surface entrypoint is a directory: %s", entryPath)
	}

	socketPath, err := waitForSessionSocket(12 * time.Second)
	if err != nil {
		return err
	}

	qsPath, err := exec.LookPath("qs")
	if err != nil {
		return fmt.Errorf("quickshell executable not found: %w", err)
	}

	env := os.Environ()
	env = setProcessEnv(env, "CYSHELL_SOCKET", socketPath)
	env = setProcessEnv(env, "CYSHELL_UI_ROLE", spec.Role)
	env = setProcessEnv(env, "QS_APP_ID", "com.cytechteam.cyshell")
	if spec.Role == "shell" {
		env = setProcessEnv(env, "CYSHELL_EXTERNAL_SETTINGS", "1")
		env = setProcessEnv(env, "CYSHELL_EXTERNAL_PANEL", "1")
		env = setProcessEnv(env, "CYSHELL_EXTERNAL_DESKTOP", "1")
		env = setProcessEnv(env, "CYSHELL_EXTERNAL_OSD", "1")
	}
	if os.Getenv("QT_QPA_PLATFORM") == "" {
		env = setProcessEnv(env, "QT_QPA_PLATFORM", "wayland;xcb")
	}
	if self, err := os.Executable(); err == nil {
		env = setProcessEnv(env, "CYSHELL_EXECUTABLE", self)
	}
	for _, item := range dmsExtraEnv(configPath) {
		if key, value, ok := strings.Cut(item, "="); ok {
			env = setProcessEnv(env, key, value)
		}
	}

	return syscall.Exec(qsPath, []string{"qs", "-n", "-p", entryPath}, env)
}

func callSurfaceIPC(role, target, method string, args []string) (string, error) {
	pid, ok := surfaceServicePID(role)
	if !ok {
		return "", fmt.Errorf("surface %q is not running", role)
	}
	callArgs := []string{"ipc", "--pid", strconv.Itoa(pid), "call", target, method}
	callArgs = append(callArgs, args...)
	out, err := exec.Command("qs", callArgs...).CombinedOutput()
	if err != nil {
		message := strings.TrimSpace(string(out))
		if message != "" {
			return "", fmt.Errorf("refresh %s: %s", role, message)
		}
		return "", fmt.Errorf("refresh %s: %w", role, err)
	}
	return strings.TrimSpace(string(out)), nil
}

func printSurfaceStatus(role string) error {
	spec, ok := surfaceSpecs[role]
	if !ok {
		return unknownSurface(role)
	}
	systemctl, err := exec.LookPath("systemctl")
	if err != nil {
		return fmt.Errorf("systemctl is required for surface status: %w", err)
	}
	stateOut, _ := exec.Command(systemctl, "--user", "is-active", spec.Unit).CombinedOutput()
	state := strings.TrimSpace(string(stateOut))
	if state == "" {
		state = "unknown"
	}
	pidOut, _ := exec.Command(systemctl, "--user", "show", "-p", "MainPID", "--value", spec.Unit).CombinedOutput()
	pid := strings.TrimSpace(string(pidOut))
	if pid == "" {
		pid = "0"
	}
	fmt.Printf("%-9s %-10s pid=%s unit=%s\n", role, state, pid, spec.Unit)
	return nil
}

func callSettingsIPC(cmd *cobra.Command, method string, args []string) error {
	method = strings.TrimSpace(method)
	if method == "" {
		method = "open"
	}

	if err := startUserUnit(surfaceSpecs["settings"].Unit); err != nil {
		return err
	}
	deadline := time.Now().Add(7 * time.Second)
	var lastErr error
	for time.Now().Before(deadline) {
		pid, ok := surfaceServicePID("settings")
		if !ok {
			lastErr = fmt.Errorf("settings surface has no live PID")
			time.Sleep(100 * time.Millisecond)
			continue
		}
		callArgs := []string{"ipc", "--pid", strconv.Itoa(pid), "call", "settings", method}
		callArgs = append(callArgs, args...)
		proc := exec.Command("qs", callArgs...)
		out, err := proc.CombinedOutput()
		if err == nil {
			if text := strings.TrimSpace(string(out)); text != "" {
				fmt.Println(text)
			}
			return nil
		}
		lastErr = err
		time.Sleep(100 * time.Millisecond)
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("IPC target did not become ready")
	}
	return fmt.Errorf("CyShell Settings IPC did not become ready: %w", lastErr)
}

func startUserUnit(unit string) error {
	return runUserUnit("start", unit)
}

func runUserUnit(action, unit string) error {
	systemctl, err := exec.LookPath("systemctl")
	if err != nil {
		return fmt.Errorf("systemctl is required for independent CyShell surfaces: %w", err)
	}
	proc := exec.Command(systemctl, "--user", action, unit)
	if out, err := proc.CombinedOutput(); err != nil {
		message := strings.TrimSpace(string(out))
		if message != "" {
			return fmt.Errorf("%s %s: %s", action, unit, message)
		}
		return fmt.Errorf("%s %s: %w", action, unit, err)
	}
	return nil
}

func waitForSessionSocket(timeout time.Duration) (string, error) {
	deadline := time.Now().Add(timeout)
	for {
		if path, ok := shellApp.SessionSocketPath(); ok && socketExists(path) {
			return path, nil
		}

		runtimeDir := os.Getenv("XDG_RUNTIME_DIR")
		if runtimeDir == "" {
			runtimeDir = filepath.Join("/run/user", strconv.Itoa(os.Getuid()))
		}
		stable := filepath.Join(runtimeDir, "cyshell-current.sock")
		if socketExists(stable) {
			return stable, nil
		}
		if resolved, err := filepath.EvalSymlinks(stable); err == nil && socketExists(resolved) {
			return stable, nil
		}

		// systemd user managers do not always retain WAYLAND_DISPLAY. Fall back
		// to live CyShell parent PIDs instead of a mutable cyshell-current.sock
		// symlink so a backend restart cannot leave a newly launched role stale.
		for _, pid := range shellApp.PIDs() {
			path := filepath.Join(runtimeDir, fmt.Sprintf("cyshell-%d.sock", pid))
			if socketExists(path) {
				return path, nil
			}
		}

		if time.Now().After(deadline) {
			return "", fmt.Errorf("CyShell core socket did not become ready")
		}
		time.Sleep(100 * time.Millisecond)
	}
}

func surfaceServicePID(role string) (int, bool) {
	spec, ok := surfaceSpecs[role]
	if !ok {
		return 0, false
	}
	out, err := exec.Command("systemctl", "--user", "show", "-p", "MainPID", "--value", spec.Unit).Output()
	if err != nil {
		return 0, false
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(out)))
	return pid, err == nil && pid > 0
}

func socketExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode()&os.ModeSocket != 0
}

func setProcessEnv(env []string, key, value string) []string {
	prefix := key + "="
	out := make([]string, 0, len(env)+1)
	for _, item := range env {
		if strings.HasPrefix(item, prefix) {
			continue
		}
		out = append(out, item)
	}
	return append(out, prefix+value)
}
