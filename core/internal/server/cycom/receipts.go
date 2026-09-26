package cycom

import (
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
)

const actionReceiptTTL = 10 * time.Minute

type ActionReceipt struct {
	ID        string `json:"id"`
	Kind      string `json:"kind"`
	Action    string `json:"action"`
	Target    string `json:"target,omitempty"`
	Value     string `json:"value,omitempty"`
	CreatedAt int64  `json:"createdAt"`
	ExpiresAt int64  `json:"expiresAt"`
	CanUndo   bool   `json:"canUndo"`
}

type actionReceiptRecord struct {
	Receipt    ActionReceipt
	UndoKind   string
	UndoAction string
	UndoValue  string
}

func (m *Manager) issueActionReceipt(action, value, undoAction, undoValue string) ActionReceipt {
	return m.issueSemanticReceipt("machine", action, "", value, "machine", undoAction, undoValue)
}

func (m *Manager) issueSettingReceipt(key, value, previousValue string) ActionReceipt {
	return m.issueSemanticReceipt("setting", "settings.set", strings.TrimSpace(key), value, "setting", strings.TrimSpace(key), previousValue)
}

func (m *Manager) issueSemanticReceipt(kind, action, target, value, undoKind, undoAction, undoValue string) ActionReceipt {
	now := time.Now()
	receipt := ActionReceipt{
		ID:        fmt.Sprintf("action-%d", m.receiptID.Add(1)),
		Kind:      strings.TrimSpace(kind),
		Action:    strings.TrimSpace(action),
		Target:    strings.TrimSpace(target),
		Value:     strings.TrimSpace(value),
		CreatedAt: now.UnixMilli(),
		ExpiresAt: now.Add(actionReceiptTTL).UnixMilli(),
		CanUndo:   strings.TrimSpace(undoAction) != "",
	}
	if !receipt.CanUndo {
		return receipt
	}
	m.receiptsMu.Lock()
	m.pruneActionReceiptsLocked(now)
	m.actionReceipts[receipt.ID] = actionReceiptRecord{
		Receipt:    receipt,
		UndoKind:   strings.TrimSpace(undoKind),
		UndoAction: strings.TrimSpace(undoAction),
		UndoValue:  strings.TrimSpace(undoValue),
	}
	m.receiptsMu.Unlock()
	m.broadcastState()
	time.AfterFunc(actionReceiptTTL+time.Second, func() {
		if m.expireActionReceipt(receipt.ID) {
			m.broadcastState()
		}
	})
	return receipt
}

func (m *Manager) ActionReceipts() []ActionReceipt {
	now := time.Now()
	m.receiptsMu.Lock()
	defer m.receiptsMu.Unlock()
	m.pruneActionReceiptsLocked(now)
	items := make([]ActionReceipt, 0, len(m.actionReceipts))
	for _, record := range m.actionReceipts {
		items = append(items, record.Receipt)
	}
	// IDs are monotonic within the process, so newest creation time gives a
	// predictable "undo last action" list for both models and Settings.
	sortActionReceiptsNewestFirst(items)
	return items
}

func sortActionReceiptsNewestFirst(items []ActionReceipt) {
	for i := 1; i < len(items); i++ {
		for j := i; j > 0 && items[j].CreatedAt > items[j-1].CreatedAt; j-- {
			items[j], items[j-1] = items[j-1], items[j]
		}
	}
}

func (m *Manager) actionReceiptForUndo(id string) (actionReceiptRecord, error) {
	id = strings.TrimSpace(id)
	if id == "" {
		return actionReceiptRecord{}, errors.New("receipt is required")
	}
	now := time.Now()
	m.receiptsMu.Lock()
	defer m.receiptsMu.Unlock()
	m.pruneActionReceiptsLocked(now)
	record, ok := m.actionReceipts[id]
	if !ok {
		return actionReceiptRecord{}, fmt.Errorf("action receipt %q is unavailable or expired", id)
	}
	return record, nil
}

func (m *Manager) consumeActionReceipt(id string) {
	m.receiptsMu.Lock()
	_, existed := m.actionReceipts[id]
	delete(m.actionReceipts, id)
	m.receiptsMu.Unlock()
	if existed {
		m.broadcastState()
	}
}

func (m *Manager) expireActionReceipt(id string) bool {
	now := time.Now().UnixMilli()
	m.receiptsMu.Lock()
	defer m.receiptsMu.Unlock()
	record, ok := m.actionReceipts[id]
	if !ok || record.Receipt.ExpiresAt > now {
		return false
	}
	delete(m.actionReceipts, id)
	return true
}

func (m *Manager) pruneActionReceiptsLocked(now time.Time) {
	for id, record := range m.actionReceipts {
		if record.Receipt.ExpiresAt <= now.UnixMilli() {
			delete(m.actionReceipts, id)
		}
	}
}

func executeReceiptUndo(record actionReceiptRecord) (string, error) {
	switch record.UndoKind {
	case "machine":
		return executeMachineAction(record.UndoAction, record.UndoValue)
	case "setting":
		result, err := callShellIPC("settings", "set", []string{record.UndoAction, record.UndoValue})
		if err != nil {
			return "", err
		}
		if result != "SETTINGS_SET_SUCCESS" {
			return "", fmt.Errorf("CyShell rejected setting rollback: %s", result)
		}
		return result, nil
	default:
		return "", fmt.Errorf("unsupported rollback kind %q", record.UndoKind)
	}
}

func desktopUndoFromState(action string, state any) (string, string, bool) {
	root, ok := state.(map[string]any)
	if !ok {
		return "", "", false
	}
	machine, ok := objectAt(root, "machine")
	if !ok {
		return "", "", false
	}
	action = strings.TrimSpace(action)
	switch action {
	case "wifi.toggle", "wifi.enable", "wifi.disable":
		wifi, ok := objectAtPath(machine, "network", "wifi")
		if !ok {
			return "", "", false
		}
		enabled, ok := wifi["enabled"].(bool)
		if !ok {
			return "", "", false
		}
		if enabled {
			return "wifi.enable", "", true
		}
		return "wifi.disable", "", true
	case "bluetooth.toggle", "bluetooth.enable", "bluetooth.disable":
		bluetooth, ok := objectAt(machine, "bluetooth")
		if !ok {
			return "", "", false
		}
		enabled, ok := bluetooth["enabled"].(bool)
		if !ok {
			return "", "", false
		}
		if enabled {
			return "bluetooth.enable", "", true
		}
		return "bluetooth.disable", "", true
	case "audio.volume.set":
		output, ok := objectAtPath(machine, "audio", "output")
		if !ok {
			return "", "", false
		}
		return numericUndo("audio.volume.set", output["volume"])
	case "audio.mute.toggle", "audio.mute.set":
		output, ok := objectAtPath(machine, "audio", "output")
		if !ok {
			return "", "", false
		}
		muted, ok := output["muted"].(bool)
		if !ok {
			return "", "", false
		}
		return "audio.mute.set", strconv.FormatBool(muted), true
	case "mic.volume.set":
		input, ok := objectAtPath(machine, "audio", "input")
		if !ok {
			return "", "", false
		}
		return numericUndo("mic.volume.set", input["volume"])
	case "mic.mute.toggle", "mic.mute.set":
		input, ok := objectAtPath(machine, "audio", "input")
		if !ok {
			return "", "", false
		}
		muted, ok := input["muted"].(bool)
		if !ok {
			return "", "", false
		}
		return "mic.mute.set", strconv.FormatBool(muted), true
	case "brightness.set":
		brightness, ok := objectAt(machine, "brightness")
		if !ok {
			return "", "", false
		}
		return numericUndo("brightness.set", brightness["level"])
	case "power.profile.set":
		power, ok := objectAt(machine, "powerProfile")
		if !ok {
			return "", "", false
		}
		profile, ok := power["profile"].(string)
		if !ok || strings.TrimSpace(profile) == "" || profile == "unavailable" {
			return "", "", false
		}
		return "power.profile.set", profile, true
	default:
		return "", "", false
	}
}

func numericUndo(action string, value any) (string, string, bool) {
	switch number := value.(type) {
	case float64:
		return action, strconv.FormatFloat(number, 'f', -1, 64), true
	case float32:
		return action, strconv.FormatFloat(float64(number), 'f', -1, 64), true
	case int:
		return action, strconv.Itoa(number), true
	case int64:
		return action, strconv.FormatInt(number, 10), true
	case json.Number:
		return action, string(number), true
	default:
		return "", "", false
	}
}

func objectAt(root map[string]any, key string) (map[string]any, bool) {
	value, ok := root[key].(map[string]any)
	return value, ok
}

func objectAtPath(root map[string]any, keys ...string) (map[string]any, bool) {
	current := root
	for _, key := range keys {
		next, ok := current[key].(map[string]any)
		if !ok {
			return nil, false
		}
		current = next
	}
	return current, true
}
