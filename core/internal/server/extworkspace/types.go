package extworkspace

import (
	"sort"
	"sync"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/proto/ext_workspace"
	wlclient "github.com/AvengeMedia/dankgo/wayland/client"
)

type Workspace struct {
	ObjectID      uint32   `json:"objectId"`
	ID            string   `json:"id,omitempty"`
	Name          string   `json:"name"`
	GroupID       uint32   `json:"groupId,omitempty"`
	Coordinates   []uint32 `json:"coordinates,omitempty"`
	Active        bool     `json:"active"`
	Urgent        bool     `json:"urgent"`
	Hidden        bool     `json:"hidden"`
	CanActivate   bool     `json:"canActivate"`
	CanDeactivate bool     `json:"canDeactivate"`
	CanRemove     bool     `json:"canRemove"`
	CanAssign     bool     `json:"canAssign"`
}

type Group struct {
	ObjectID           uint32   `json:"objectId"`
	Outputs            []string `json:"outputs"`
	WorkspaceObjectIDs []uint32 `json:"workspaceObjectIds"`
	CanCreateWorkspace bool     `json:"canCreateWorkspace"`
}

type State struct {
	Available  bool        `json:"available"`
	Workspaces []Workspace `json:"workspaces"`
	Groups     []Group     `json:"groups"`
}

type workspaceState struct {
	handle       *ext_workspace.ExtWorkspaceHandleV1
	id           string
	name         string
	groupID      uint32
	coordinates  []uint32
	state        uint32
	capabilities uint32
	removed      bool
}

type groupState struct {
	handle       *ext_workspace.ExtWorkspaceGroupHandleV1
	capabilities uint32
	outputs      map[uint32]struct{}
	workspaces   map[uint32]struct{}
	removed      bool
}

type Manager struct {
	display  wlclient.WaylandDisplay
	ctx      *wlclient.Context
	registry *wlclient.Registry
	manager  *ext_workspace.ExtWorkspaceManagerV1
	post     func(func())

	mu          sync.RWMutex
	available   bool
	workspaces  map[uint32]*workspaceState
	groups      map[uint32]*groupState
	outputNames map[uint32]string
	outputs     map[uint32]*wlclient.Output
	subscribers map[string]chan State
}

func (m *Manager) GetState() State {
	m.mu.RLock()
	defer m.mu.RUnlock()

	state := State{Available: m.available, Workspaces: []Workspace{}, Groups: []Group{}}
	for _, ws := range m.workspaces {
		if ws == nil || ws.removed || ws.handle == nil {
			continue
		}
		caps := ws.capabilities
		state.Workspaces = append(state.Workspaces, Workspace{
			ObjectID:      ws.handle.ID(),
			ID:            ws.id,
			Name:          ws.name,
			GroupID:       ws.groupID,
			Coordinates:   append([]uint32(nil), ws.coordinates...),
			Active:        ws.state&uint32(ext_workspace.ExtWorkspaceHandleV1StateActive) != 0,
			Urgent:        ws.state&uint32(ext_workspace.ExtWorkspaceHandleV1StateUrgent) != 0,
			Hidden:        ws.state&uint32(ext_workspace.ExtWorkspaceHandleV1StateHidden) != 0,
			CanActivate:   caps&uint32(ext_workspace.ExtWorkspaceHandleV1WorkspaceCapabilitiesActivate) != 0,
			CanDeactivate: caps&uint32(ext_workspace.ExtWorkspaceHandleV1WorkspaceCapabilitiesDeactivate) != 0,
			CanRemove:     caps&uint32(ext_workspace.ExtWorkspaceHandleV1WorkspaceCapabilitiesRemove) != 0,
			CanAssign:     caps&uint32(ext_workspace.ExtWorkspaceHandleV1WorkspaceCapabilitiesAssign) != 0,
		})
	}
	for _, group := range m.groups {
		if group == nil || group.removed || group.handle == nil {
			continue
		}
		out := Group{
			ObjectID:           group.handle.ID(),
			Outputs:            []string{},
			WorkspaceObjectIDs: []uint32{},
			CanCreateWorkspace: group.capabilities&uint32(ext_workspace.ExtWorkspaceGroupHandleV1GroupCapabilitiesCreateWorkspace) != 0,
		}
		for id := range group.outputs {
			name := m.outputNames[id]
			if name == "" {
				name = "output"
			}
			out.Outputs = append(out.Outputs, name)
		}
		for id := range group.workspaces {
			out.WorkspaceObjectIDs = append(out.WorkspaceObjectIDs, id)
		}
		sort.Strings(out.Outputs)
		sort.Slice(out.WorkspaceObjectIDs, func(i, j int) bool { return out.WorkspaceObjectIDs[i] < out.WorkspaceObjectIDs[j] })
		state.Groups = append(state.Groups, out)
	}
	sort.Slice(state.Workspaces, func(i, j int) bool {
		a, b := state.Workspaces[i], state.Workspaces[j]
		if a.GroupID != b.GroupID {
			return a.GroupID < b.GroupID
		}
		if len(a.Coordinates) > 0 && len(b.Coordinates) > 0 && a.Coordinates[0] != b.Coordinates[0] {
			return a.Coordinates[0] < b.Coordinates[0]
		}
		if a.Name != b.Name {
			return a.Name < b.Name
		}
		return a.ObjectID < b.ObjectID
	})
	sort.Slice(state.Groups, func(i, j int) bool { return state.Groups[i].ObjectID < state.Groups[j].ObjectID })
	return state
}

func (m *Manager) Subscribe(id string) chan State {
	m.mu.Lock()
	defer m.mu.Unlock()
	ch := make(chan State, 16)
	m.subscribers[id] = ch
	return ch
}

func (m *Manager) Unsubscribe(id string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if ch, ok := m.subscribers[id]; ok {
		delete(m.subscribers, id)
		close(ch)
	}
}
