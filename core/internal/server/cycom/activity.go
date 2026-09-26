package cycom

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

const agentRecentActivityLimit = 64

type CallOrigin struct {
	Kind    string `json:"kind"`
	Name    string `json:"name"`
	Version string `json:"version,omitempty"`
}

type Activity struct {
	ID         string     `json:"id"`
	Tool       string     `json:"tool"`
	Origin     CallOrigin `json:"origin"`
	Reason     string     `json:"reason,omitempty"`
	Scopes     []string   `json:"scopes,omitempty"`
	Status     string     `json:"status"`
	StartedAt  int64      `json:"startedAt"`
	FinishedAt int64      `json:"finishedAt,omitempty"`
	DurationMs int64      `json:"durationMs,omitempty"`
	Error      string     `json:"error,omitempty"`
}

type Event struct {
	Kind             string             `json:"kind"`
	State            *State             `json:"state,omitempty"`
	PendingApprovals *[]ApprovalRequest `json:"pendingApprovals,omitempty"`
	RecentActivity   *[]Activity        `json:"recentActivity,omitempty"`
	ActionReceipts   *[]ActionReceipt   `json:"actionReceipts,omitempty"`
	Activity         *Activity          `json:"activity,omitempty"`
}

func (m *Manager) Subscribe(id string) chan Event {
	m.eventsMu.Lock()
	defer m.eventsMu.Unlock()
	if previous, ok := m.eventSubscribers[id]; ok {
		close(previous)
	}
	ch := make(chan Event, 64)
	m.eventSubscribers[id] = ch
	return ch
}

func (m *Manager) Unsubscribe(id string) {
	m.eventsMu.Lock()
	defer m.eventsMu.Unlock()
	if ch, ok := m.eventSubscribers[id]; ok {
		delete(m.eventSubscribers, id)
		close(ch)
	}
}

func (m *Manager) SnapshotEvent() Event {
	state := m.RuntimeState()
	pending := m.PendingApprovals()
	recent := m.RecentActivity()
	receipts := m.ActionReceipts()
	return Event{
		Kind:             "snapshot",
		State:            &state,
		PendingApprovals: &pending,
		RecentActivity:   &recent,
		ActionReceipts:   &receipts,
	}
}

func (m *Manager) RecentActivity() []Activity {
	m.activityMu.Lock()
	defer m.activityMu.Unlock()
	out := make([]Activity, len(m.recentActivity))
	for i, activity := range m.recentActivity {
		out[i] = cloneActivity(activity)
	}
	return out
}

func cloneActivity(activity Activity) Activity {
	activity.Scopes = append([]string(nil), activity.Scopes...)
	return activity
}

func (m *Manager) broadcast(event Event) {
	m.eventsMu.Lock()
	defer m.eventsMu.Unlock()
	for _, ch := range m.eventSubscribers {
		select {
		case ch <- event:
		default:
		}
	}
}

func (m *Manager) broadcastState() {
	state := m.RuntimeState()
	pending := m.PendingApprovals()
	receipts := m.ActionReceipts()
	m.broadcast(Event{
		Kind:             "state",
		State:            &state,
		PendingApprovals: &pending,
		ActionReceipts:   &receipts,
	})
}

func (m *Manager) beginActivity(name string, raw json.RawMessage, origin CallOrigin) Activity {
	now := time.Now()
	activity := Activity{
		ID:        fmt.Sprintf("activity-%d", m.activityID.Add(1)),
		Tool:      name,
		Origin:    normalizeCallOrigin(origin),
		Reason:    activityReason(raw),
		Scopes:    append([]string(nil), m.requiredScopes(name, raw)...),
		Status:    "running",
		StartedAt: now.UnixMilli(),
	}
	m.activityMu.Lock()
	m.recentActivity = append([]Activity{activity}, m.recentActivity...)
	if len(m.recentActivity) > agentRecentActivityLimit {
		m.recentActivity = m.recentActivity[:agentRecentActivityLimit]
	}
	m.activityMu.Unlock()
	state := m.RuntimeState()
	copyActivity := cloneActivity(activity)
	m.broadcast(Event{Kind: "activity", State: &state, Activity: &copyActivity})
	return activity
}

func (m *Manager) finishActivity(activity Activity, err error, finished time.Time) Activity {
	activity.FinishedAt = finished.UnixMilli()
	activity.DurationMs = max(0, finished.Sub(time.UnixMilli(activity.StartedAt)).Milliseconds())
	activity.Status = "succeeded"
	if err != nil {
		activity.Status = "failed"
		if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
			activity.Status = "canceled"
		}
		activity.Error = compactActivityError(err.Error())
	}
	m.activityMu.Lock()
	for i := range m.recentActivity {
		if m.recentActivity[i].ID == activity.ID {
			m.recentActivity[i] = activity
			break
		}
	}
	m.activityMu.Unlock()
	state := m.RuntimeState()
	copyActivity := cloneActivity(activity)
	m.broadcast(Event{Kind: "activity", State: &state, Activity: &copyActivity})
	return activity
}

func (m *Manager) ClearRecentActivity() {
	m.activityMu.Lock()
	m.recentActivity = make([]Activity, 0, agentRecentActivityLimit)
	m.activityMu.Unlock()
	state := m.RuntimeState()
	recent := []Activity{}
	m.broadcast(Event{Kind: "activity_reset", State: &state, RecentActivity: &recent})
}

func normalizeCallOrigin(origin CallOrigin) CallOrigin {
	origin.Kind = strings.ToLower(strings.TrimSpace(origin.Kind))
	origin.Name = compactActivityText(origin.Name, 80)
	origin.Version = compactActivityText(origin.Version, 40)
	if origin.Kind == "" {
		origin.Kind = "internal"
	}
	if origin.Name == "" {
		switch origin.Kind {
		case "assistant":
			origin.Name = "Built-in Assistant"
		case "mcp":
			origin.Name = "External MCP client"
		case "ipc":
			origin.Name = "Local IPC client"
		default:
			origin.Name = "CyShell"
		}
	}
	return origin
}

func activityReason(raw json.RawMessage) string {
	var args map[string]any
	if json.Unmarshal(raw, &args) != nil {
		return ""
	}
	reason, _ := args["reason"].(string)
	return compactActivityText(reason, 280)
}

func compactActivityError(value string) string {
	return compactActivityText(value, 360)
}

func compactActivityText(value string, limit int) string {
	value = strings.Join(strings.Fields(value), " ")
	runes := []rune(value)
	if limit > 0 && len(runes) > limit {
		return string(runes[:limit]) + "…"
	}
	return value
}
