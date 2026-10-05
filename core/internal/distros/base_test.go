package distros

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/Cytech-Team/CyShell-Desktop/core/internal/deps"
	"github.com/Cytech-Team/CyShell-Desktop/core/internal/utils"
)

func TestBaseDistribution_detectCyShell_NotInstalled(t *testing.T) {
	originalHome := os.Getenv("HOME")
	defer os.Setenv("HOME", originalHome)

	tempDir := t.TempDir()
	os.Setenv("HOME", tempDir)

	logChan := make(chan string, 10)
	defer close(logChan)

	base := NewBaseDistribution(logChan)
	dep := base.detectCyShell()

	if dep.Status != deps.StatusMissing {
		t.Errorf("Expected StatusMissing, got %d", dep.Status)
	}

	if dep.Name != "CyShell" {
		t.Errorf("Expected name 'CyShell', got %s", dep.Name)
	}

	if !dep.Required {
		t.Error("Expected Required to be true")
	}
}

func TestBaseDistribution_detectCyShell_Installed(t *testing.T) {
	if !utils.CommandExists("git") {
		t.Skip("git not available")
	}

	tempDir := t.TempDir()
	cyShellPath := filepath.Join(tempDir, ".config", "quickshell", "cyshell")
	os.MkdirAll(cyShellPath, 0o755)

	originalHome := os.Getenv("HOME")
	defer os.Setenv("HOME", originalHome)
	os.Setenv("HOME", tempDir)

	exec.Command("git", "init", cyShellPath).Run()
	exec.Command("git", "-C", cyShellPath, "config", "user.email", "test@test.com").Run()
	exec.Command("git", "-C", cyShellPath, "config", "user.name", "Test User").Run()
	exec.Command("git", "-C", cyShellPath, "checkout", "-b", "master").Run()

	testFile := filepath.Join(cyShellPath, "test.txt")
	os.WriteFile(testFile, []byte("test"), 0o644)
	exec.Command("git", "-C", cyShellPath, "add", ".").Run()
	exec.Command("git", "-C", cyShellPath, "commit", "-m", "initial").Run()

	logChan := make(chan string, 10)
	defer close(logChan)

	base := NewBaseDistribution(logChan)
	dep := base.detectCyShell()

	if dep.Status == deps.StatusMissing {
		t.Error("Expected CyShell to be detected as installed")
	}

	if dep.Name != "CyShell" {
		t.Errorf("Expected name 'CyShell', got %s", dep.Name)
	}

	if !dep.Required {
		t.Error("Expected Required to be true")
	}

	t.Logf("Status: %d, Version: %s", dep.Status, dep.Version)
}

func TestBaseDistribution_detectCyShell_DirectoryWithoutGit(t *testing.T) {
	tempDir := t.TempDir()
	cyShellPath := filepath.Join(tempDir, ".config", "quickshell", "cyshell")
	os.MkdirAll(cyShellPath, 0o755)

	originalHome := os.Getenv("HOME")
	defer os.Setenv("HOME", originalHome)
	os.Setenv("HOME", tempDir)

	logChan := make(chan string, 10)
	defer close(logChan)

	base := NewBaseDistribution(logChan)
	dep := base.detectCyShell()

	if dep.Status == deps.StatusMissing {
		t.Error("Expected CyShell to be detected as present")
	}

	if dep.Name != "CyShell" {
		t.Errorf("Expected name 'CyShell', got %s", dep.Name)
	}

	if !dep.Required {
		t.Error("Expected Required to be true")
	}
}
