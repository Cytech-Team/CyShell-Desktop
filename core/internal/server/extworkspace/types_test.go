package extworkspace

import (
	"testing"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/proto/ext_workspace"
)

func TestWorkspaceCapabilityProjection(t *testing.T) {
	m := &Manager{
		available: true,
		workspaces: map[uint32]*workspaceState{
			1: {
				handle:       &ext_workspace.ExtWorkspaceHandleV1{},
				name:         "dev",
				state:        uint32(ext_workspace.ExtWorkspaceHandleV1StateActive | ext_workspace.ExtWorkspaceHandleV1StateUrgent),
				capabilities: uint32(ext_workspace.ExtWorkspaceHandleV1WorkspaceCapabilitiesActivate | ext_workspace.ExtWorkspaceHandleV1WorkspaceCapabilitiesRemove),
			},
		},
		groups: map[uint32]*groupState{}, outputNames: map[uint32]string{}, subscribers: map[string]chan State{},
	}
	// A zero-value protocol handle has object id 0, which is fine for testing projection.
	state := m.GetState()
	if !state.Available || len(state.Workspaces) != 1 {
		t.Fatalf("unexpected state: %#v", state)
	}
	ws := state.Workspaces[0]
	if !ws.Active || !ws.Urgent || !ws.CanActivate || !ws.CanRemove || ws.Hidden {
		t.Fatalf("unexpected workspace projection: %#v", ws)
	}
}
