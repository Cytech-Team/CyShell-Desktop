package providers

import (
	"encoding/xml"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeLabwcFixture(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "rc.xml")
	if err := os.WriteFile(path, []byte(content), 0o640); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestLabwcKeyRoundTrip(t *testing.T) {
	tests := map[string]string{
		"Super+Shift+A":   "W-S-a",
		"Ctrl+Alt+Delete": "C-A-Delete",
		"Super+space":     "W-space",
		"Print":           "Print",
	}
	for generic, labwc := range tests {
		if got := genericKeyToLabwc(generic); got != labwc {
			t.Fatalf("genericKeyToLabwc(%q) = %q, want %q", generic, got, labwc)
		}
		if got := normalizeLabwcKey(labwcKeyToGeneric(labwc)); got != normalizeLabwcKey(generic) {
			t.Fatalf("round trip %q -> %q", generic, got)
		}
	}
}

func TestLabwcCheatSheetUsesEffectiveManagedOverride(t *testing.T) {
	path := writeLabwcFixture(t, `<?xml version="1.0"?>
<labwc_config>
  <keyboard>
    <default />
    <keybind key="W-a"><action name="Close" /></keybind>
    `+labwcManagedBegin+`
    <!-- CyShell: Open the native Agent -->
    <keybind key="W-a"><action name="Execute" command="dms agent open" /></keybind>
    <keybind key="W-Right"><action name="GoToDesktop" to="right" wrap="yes" /></keybind>
    `+labwcManagedEnd+`
  </keyboard>
</labwc_config>
`)
	provider := NewLabwcProvider(path)
	sheet, err := provider.GetCheatSheet()
	if err != nil {
		t.Fatal(err)
	}
	if sheet.Provider != "labwc" || !sheet.DMSBindsIncluded {
		t.Fatalf("unexpected sheet metadata: %#v", sheet)
	}
	var foundAgent, foundWorkspace bool
	for _, bind := range sheet.Binds["Execute"] {
		if bind.Key == "Super+A" {
			foundAgent = true
			if bind.Action != "spawn dms agent open" || bind.Description != "Open the native Agent" || bind.Source != "dms" {
				t.Fatalf("unexpected managed bind: %#v", bind)
			}
		}
	}
	for _, bind := range sheet.Binds["Workspace"] {
		if bind.Key == "Super+Right" && bind.Action == "GoToDesktop right wrap=yes" {
			foundWorkspace = true
		}
	}
	if !foundAgent || !foundWorkspace {
		t.Fatalf("missing expected binds: %#v", sheet.Binds)
	}
}

func TestLabwcSetBindPreservesConfigAndWritesManagedBlock(t *testing.T) {
	path := writeLabwcFixture(t, `<?xml version="1.0"?>
<labwc_config>
  <!-- keep me -->
  <keyboard>
    <default />
    <keybind key="A-F4"><action name="Close" /></keybind>
  </keyboard>
  <theme><name>CyShell</name></theme>
</labwc_config>
`)
	provider := NewLabwcProvider(path)
	if err := provider.SetBind("Super+Shift+A", `spawn sh -c "notify-send 'A & B'"`, "Agent -- shortcut", map[string]any{
		"allow-when-locked": true,
		"allow-inhibiting":  false,
		"flags":             "r",
	}); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	for _, wanted := range []string{"<!-- keep me -->", "<theme><name>CyShell</name></theme>", labwcManagedBegin, labwcManagedEnd, `key="W-S-a"`, `onRelease="yes"`, `allowWhenLocked="yes"`, `overrideInhibition="yes"`, `A &amp; B`} {
		if !strings.Contains(text, wanted) {
			t.Fatalf("written config missing %q:\n%s", wanted, text)
		}
	}
	var parsed labwcDocument
	if err := xml.Unmarshal(data, &parsed); err != nil {
		t.Fatalf("written rc.xml is invalid: %v\n%s", err, text)
	}
	stat, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if got := stat.Mode().Perm(); got != 0o640 {
		t.Fatalf("mode = %o, want 640", got)
	}
}

func TestLabwcRemoveManagedBindRevealsOriginal(t *testing.T) {
	path := writeLabwcFixture(t, `<?xml version="1.0"?>
<labwc_config><keyboard>
  <keybind key="W-a"><action name="Close" /></keybind>
</keyboard></labwc_config>
`)
	provider := NewLabwcProvider(path)
	if err := provider.SetBind("Super+A", "spawn dms agent open", "Agent", nil); err != nil {
		t.Fatal(err)
	}
	if err := provider.RemoveBind("Super+A"); err != nil {
		t.Fatal(err)
	}
	sheet, err := provider.GetCheatSheet()
	if err != nil {
		t.Fatal(err)
	}
	binds := sheet.Binds["Window"]
	if len(binds) != 1 || binds[0].Key != "Super+A" || binds[0].Action != "Close" || binds[0].Source != "config" {
		t.Fatalf("original bind was not restored: %#v", sheet.Binds)
	}
}

func TestLabwcSetBindCreatesKeyboardSection(t *testing.T) {
	path := writeLabwcFixture(t, `<?xml version="1.0"?><labwc_config><theme><name>X</name></theme></labwc_config>`)
	provider := NewLabwcProvider(path)
	if err := provider.SetBind("Super+A", "ToggleShowDesktop", "Show desktop", nil); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var parsed labwcDocument
	if err := xml.Unmarshal(data, &parsed); err != nil {
		t.Fatal(err)
	}
	if len(parsed.Keyboard.Keybinds) != 1 || parsed.Keyboard.Keybinds[0].Key != "W-a" {
		t.Fatalf("unexpected generated keyboard section: %s", data)
	}
}

func TestLabwcManagedOverrideReportsDefault(t *testing.T) {
	path := writeLabwcFixture(t, `<?xml version="1.0"?>
<labwc_config><keyboard>
  <keybind key="W-a"><action name="Close" /></keybind>
</keyboard></labwc_config>
`)
	provider := NewLabwcProvider(path)
	if err := provider.SetBind("Super+A", "spawn dms agent open", "Agent", nil); err != nil {
		t.Fatal(err)
	}
	sheet, err := provider.GetCheatSheet()
	if err != nil {
		t.Fatal(err)
	}
	for _, bind := range sheet.Binds["Execute"] {
		if bind.Key == "Super+A" {
			if !bind.HasDefault {
				t.Fatal("managed override should report the underlying rc.xml binding as a default")
			}
			return
		}
	}
	t.Fatal("managed override missing from cheatsheet")
}

func TestLabwcReplaceBindSuppressesOriginalConfigKey(t *testing.T) {
	path := writeLabwcFixture(t, `<?xml version="1.0"?>
<labwc_config><keyboard>
  <keybind key="W-a"><action name="Close" /></keybind>
</keyboard></labwc_config>
`)
	provider := NewLabwcProvider(path)
	if err := provider.ReplaceBind("Super+A", "Super+B", "spawn dms agent open", "Agent", nil); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	if !strings.Contains(text, `key="W-a"`) || !strings.Contains(text, `name="None"`) || !strings.Contains(text, `key="W-b"`) {
		t.Fatalf("replacement did not preserve/suppress original and add new key:\n%s", text)
	}
	sheet, err := provider.GetCheatSheet()
	if err != nil {
		t.Fatal(err)
	}
	for _, binds := range sheet.Binds {
		for _, bind := range binds {
			if bind.Key == "Super+A" {
				t.Fatalf("suppressed original key should not remain visible/effective: %#v", bind)
			}
		}
	}
	foundNew := false
	for _, bind := range sheet.Binds["Execute"] {
		if bind.Key == "Super+B" && bind.Action == "spawn dms agent open" {
			foundNew = true
		}
	}
	if !foundNew {
		t.Fatalf("replacement key missing: %#v", sheet.Binds)
	}

	if err := provider.ResetBind("Super+A"); err != nil {
		t.Fatal(err)
	}
	sheet, err = provider.GetCheatSheet()
	if err != nil {
		t.Fatal(err)
	}
	restored := false
	for _, bind := range sheet.Binds["Window"] {
		if bind.Key == "Super+A" && bind.Action == "Close" {
			restored = true
		}
	}
	if !restored {
		t.Fatalf("reset did not restore original config key: %#v", sheet.Binds)
	}
}

func TestLabwcRefusesToRewriteMalformedConfig(t *testing.T) {
	path := writeLabwcFixture(t, `<labwc_config><keyboard><keybind key="W-a"><action name="Close" /></keyboard></labwc_config>`)
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	provider := NewLabwcProvider(path)
	if err := provider.SetBind("Super+B", "spawn dms agent open", "Agent", nil); err == nil {
		t.Fatal("expected malformed rc.xml to be rejected")
	}
	after, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != string(before) {
		t.Fatalf("malformed config was modified:\nbefore=%s\nafter=%s", before, after)
	}
}
