package keybinds

import (
	"encoding/json"
	"testing"

	"github.com/Cytech-Team/CyShell-Desktop/core/internal/configfrag"
)

func marshalKeys(t *testing.T, v any) map[string]json.RawMessage {
	t.Helper()
	data, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var out map[string]json.RawMessage
	if err := json.Unmarshal(data, &out); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	return out
}

func TestCyShellBindsStatusKeySpellings(t *testing.T) {
	keys := marshalKeys(t, CyShellBindsStatus{
		Exists:            true,
		Included:          true,
		IncludePosition:   2,
		TotalIncludes:     3,
		BindsAfterCyShell: 4,
		Effective:         true,
		OverriddenBy:      4,
		StatusMessage:     "CyShell binds are active",
		ConfigFormat:      "lua",
		ReadOnly:          true,
	})

	want := []string{"exists", "included", "includePosition", "totalIncludes", "bindsAfterCyShell", "effective", "overriddenBy", "statusMessage", "configFormat", "readOnly"}
	if len(keys) != len(want) {
		t.Fatalf("key count = %d, want %d: %v", len(keys), len(want), keys)
	}
	for _, key := range want {
		if _, ok := keys[key]; !ok {
			t.Errorf("missing key %q", key)
		}
	}
}

func TestCyShellBindsStatusOmitsFormatAndReadOnlyWhenUnset(t *testing.T) {
	keys := marshalKeys(t, CyShellBindsStatus{})

	if _, ok := keys["configFormat"]; ok {
		t.Error("configFormat must be omitted when empty")
	}
	if _, ok := keys["readOnly"]; ok {
		t.Error("readOnly must be omitted when false")
	}
	for _, key := range []string{"exists", "included", "includePosition", "totalIncludes", "bindsAfterCyShell", "effective", "overriddenBy", "statusMessage"} {
		if _, ok := keys[key]; !ok {
			t.Errorf("zero value must still carry %q", key)
		}
	}
}

func TestCyShellBindsStatusValuesSurviveTheWire(t *testing.T) {
	data, err := json.Marshal(CyShellBindsStatus{IncludePosition: 2, TotalIncludes: 3, BindsAfterCyShell: 4, OverriddenBy: 4, StatusMessage: "x"})
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var back CyShellBindsStatus
	if err := json.Unmarshal(data, &back); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if back.BindsAfterCyShell != 4 {
		t.Errorf("bindsAfterCyShell = %d, want 4", back.BindsAfterCyShell)
	}
	if back.IncludePosition != 2 || back.TotalIncludes != 3 {
		t.Errorf("include position/total = %d/%d, want 2/3", back.IncludePosition, back.TotalIncludes)
	}
}

func TestCyShellBindsStatusFromCarriesEveryField(t *testing.T) {
	got := CyShellBindsStatusFrom(configfrag.Status{
		Exists:              true,
		Included:            true,
		IncludePosition:     2,
		TotalIncludes:       3,
		EntriesAfterCyShell: 7,
		Effective:           true,
		OverriddenBy:        7,
		StatusMessage:       "CyShell binds are active",
		ConfigFormat:        "lua",
		ReadOnly:            true,
	})

	want := CyShellBindsStatus{
		Exists:            true,
		Included:          true,
		IncludePosition:   2,
		TotalIncludes:     3,
		BindsAfterCyShell: 7,
		Effective:         true,
		OverriddenBy:      7,
		StatusMessage:     "CyShell binds are active",
		ConfigFormat:      "lua",
		ReadOnly:          true,
	}
	if *got != want {
		t.Errorf("CyShellBindsStatusFrom = %+v, want %+v", *got, want)
	}
}

func TestCyShellBindsStatusFromKeepsAnUnseenIncludePosition(t *testing.T) {
	got := CyShellBindsStatusFrom(configfrag.BuildStatus(configfrag.NewScan(), false, 0, "", false, configfrag.Messages{Missing: "gone"}))
	if got.IncludePosition != -1 {
		t.Errorf("includePosition = %d, want -1", got.IncludePosition)
	}
	if got.StatusMessage != "gone" {
		t.Errorf("statusMessage = %q, want gone", got.StatusMessage)
	}
}
