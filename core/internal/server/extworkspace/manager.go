package extworkspace

import (
	"fmt"
	"strings"
	"time"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/log"
	"github.com/AvengeMedia/DankMaterialShell/core/internal/proto/ext_workspace"
	"github.com/AvengeMedia/DankMaterialShell/core/internal/server/wlcontext"
	wlclient "github.com/AvengeMedia/dankgo/wayland/client"
)

func NewManager(shared wlcontext.WaylandContext) (*Manager, error) {
	if shared == nil || shared.Display() == nil {
		return nil, fmt.Errorf("shared Wayland context is required")
	}
	m := &Manager{
		display:     shared.Display(),
		ctx:         shared.Display().Context(),
		post:        shared.Post,
		workspaces:  make(map[uint32]*workspaceState),
		groups:      make(map[uint32]*groupState),
		outputNames: make(map[uint32]string),
		outputs:     make(map[uint32]*wlclient.Output),
		subscribers: make(map[string]chan State),
	}
	if err := m.setupRegistry(); err != nil {
		return nil, err
	}
	return m, nil
}

func (m *Manager) setupRegistry() error {
	registry, err := m.display.GetRegistry()
	if err != nil {
		return fmt.Errorf("get Wayland registry: %w", err)
	}
	m.registry = registry
	registry.SetGlobalHandler(func(e wlclient.RegistryGlobalEvent) {
		switch e.Interface {
		case ext_workspace.ExtWorkspaceManagerV1InterfaceName:
			manager := ext_workspace.NewExtWorkspaceManagerV1(m.ctx)
			manager.SetWorkspaceGroupHandler(func(e ext_workspace.ExtWorkspaceManagerV1WorkspaceGroupEvent) {
				m.attachGroup(e.WorkspaceGroup)
			})
			manager.SetWorkspaceHandler(func(e ext_workspace.ExtWorkspaceManagerV1WorkspaceEvent) {
				m.attachWorkspace(e.Workspace)
			})
			manager.SetDoneHandler(func(ext_workspace.ExtWorkspaceManagerV1DoneEvent) {
				m.mu.Lock()
				m.available = true
				m.mu.Unlock()
				m.publish()
			})
			manager.SetFinishedHandler(func(ext_workspace.ExtWorkspaceManagerV1FinishedEvent) {
				m.mu.Lock()
				m.available = false
				m.manager = nil
				m.mu.Unlock()
				m.publish()
			})
			if err := registry.Bind(e.Name, e.Interface, min(e.Version, 1), manager); err != nil {
				log.Warnf("ExtWorkspace: failed to bind manager: %v", err)
				return
			}
			m.mu.Lock()
			m.manager = manager
			m.mu.Unlock()
			log.Info("ExtWorkspace: manager bound")
		case wlclient.OutputInterfaceName:
			m.bindOutput(registry, e)
		}
	})
	return nil
}

func (m *Manager) bindOutput(registry *wlclient.Registry, e wlclient.RegistryGlobalEvent) {
	output := wlclient.NewOutput(m.ctx)
	output.SetNameHandler(func(e wlclient.OutputNameEvent) {
		m.mu.Lock()
		m.outputNames[output.ID()] = e.Name
		m.mu.Unlock()
		m.publish()
	})
	if err := registry.Bind(e.Name, e.Interface, min(e.Version, 4), output); err != nil {
		log.Debugf("ExtWorkspace: failed to bind output: %v", err)
		return
	}
	m.mu.Lock()
	m.outputs[output.ID()] = output
	m.mu.Unlock()
}

func (m *Manager) attachWorkspace(handle *ext_workspace.ExtWorkspaceHandleV1) {
	if handle == nil {
		return
	}
	id := handle.ID()
	ws := &workspaceState{handle: handle}
	m.mu.Lock()
	m.workspaces[id] = ws
	m.mu.Unlock()

	handle.SetIdHandler(func(e ext_workspace.ExtWorkspaceHandleV1IdEvent) {
		m.mu.Lock()
		ws.id = e.Id
		m.mu.Unlock()
	})
	handle.SetNameHandler(func(e ext_workspace.ExtWorkspaceHandleV1NameEvent) {
		m.mu.Lock()
		ws.name = e.Name
		m.mu.Unlock()
	})
	handle.SetCoordinatesHandler(func(e ext_workspace.ExtWorkspaceHandleV1CoordinatesEvent) {
		coords := make([]uint32, 0, len(e.Coordinates)/4)
		for i := 0; i+4 <= len(e.Coordinates); i += 4 {
			coords = append(coords, wlclient.Uint32(e.Coordinates[i:i+4]))
		}
		m.mu.Lock()
		ws.coordinates = coords
		m.mu.Unlock()
	})
	handle.SetStateHandler(func(e ext_workspace.ExtWorkspaceHandleV1StateEvent) {
		m.mu.Lock()
		ws.state = e.State
		m.mu.Unlock()
	})
	handle.SetCapabilitiesHandler(func(e ext_workspace.ExtWorkspaceHandleV1CapabilitiesEvent) {
		m.mu.Lock()
		ws.capabilities = e.Capabilities
		m.mu.Unlock()
	})
	handle.SetRemovedHandler(func(ext_workspace.ExtWorkspaceHandleV1RemovedEvent) {
		m.mu.Lock()
		ws.removed = true
		m.mu.Unlock()
	})
}

func (m *Manager) attachGroup(handle *ext_workspace.ExtWorkspaceGroupHandleV1) {
	if handle == nil {
		return
	}
	id := handle.ID()
	group := &groupState{handle: handle, outputs: make(map[uint32]struct{}), workspaces: make(map[uint32]struct{})}
	m.mu.Lock()
	m.groups[id] = group
	m.mu.Unlock()

	handle.SetCapabilitiesHandler(func(e ext_workspace.ExtWorkspaceGroupHandleV1CapabilitiesEvent) {
		m.mu.Lock()
		group.capabilities = e.Capabilities
		m.mu.Unlock()
	})
	handle.SetOutputEnterHandler(func(e ext_workspace.ExtWorkspaceGroupHandleV1OutputEnterEvent) {
		if e.Output == nil {
			return
		}
		m.mu.Lock()
		group.outputs[e.Output.ID()] = struct{}{}
		m.mu.Unlock()
	})
	handle.SetOutputLeaveHandler(func(e ext_workspace.ExtWorkspaceGroupHandleV1OutputLeaveEvent) {
		if e.Output == nil {
			return
		}
		m.mu.Lock()
		delete(group.outputs, e.Output.ID())
		m.mu.Unlock()
	})
	handle.SetWorkspaceEnterHandler(func(e ext_workspace.ExtWorkspaceGroupHandleV1WorkspaceEnterEvent) {
		if e.Workspace == nil {
			return
		}
		wid := e.Workspace.ID()
		m.mu.Lock()
		group.workspaces[wid] = struct{}{}
		if ws := m.workspaces[wid]; ws != nil {
			ws.groupID = id
		}
		m.mu.Unlock()
	})
	handle.SetWorkspaceLeaveHandler(func(e ext_workspace.ExtWorkspaceGroupHandleV1WorkspaceLeaveEvent) {
		if e.Workspace == nil {
			return
		}
		wid := e.Workspace.ID()
		m.mu.Lock()
		delete(group.workspaces, wid)
		if ws := m.workspaces[wid]; ws != nil && ws.groupID == id {
			ws.groupID = 0
		}
		m.mu.Unlock()
	})
	handle.SetRemovedHandler(func(ext_workspace.ExtWorkspaceGroupHandleV1RemovedEvent) {
		m.mu.Lock()
		group.removed = true
		m.mu.Unlock()
	})
}

func (m *Manager) publish() {
	state := m.GetState()
	m.mu.RLock()
	defer m.mu.RUnlock()
	for _, ch := range m.subscribers {
		select {
		case ch <- state:
		default:
		}
	}
}

func (m *Manager) findWorkspace(selector string) (*workspaceState, error) {
	selector = strings.TrimSpace(selector)
	if selector == "" {
		return nil, fmt.Errorf("workspace selector is required")
	}
	m.mu.RLock()
	defer m.mu.RUnlock()
	var nameMatch *workspaceState
	for _, ws := range m.workspaces {
		if ws == nil || ws.removed || ws.handle == nil {
			continue
		}
		if ws.id != "" && ws.id == selector {
			return ws, nil
		}
		if fmt.Sprint(ws.handle.ID()) == selector {
			return ws, nil
		}
		if ws.name == selector {
			if nameMatch != nil {
				return nil, fmt.Errorf("workspace name %q is ambiguous; use id or objectId", selector)
			}
			nameMatch = ws
		}
	}
	if nameMatch != nil {
		return nameMatch, nil
	}
	return nil, fmt.Errorf("workspace %q not found", selector)
}

func (m *Manager) Activate(selector string) error {
	ws, err := m.findWorkspace(selector)
	if err != nil {
		return err
	}
	if ws.capabilities&uint32(ext_workspace.ExtWorkspaceHandleV1WorkspaceCapabilitiesActivate) == 0 {
		return fmt.Errorf("workspace %q does not advertise activate capability", selector)
	}
	return m.request(func() error {
		if err := ws.handle.Activate(); err != nil {
			return err
		}
		if m.manager == nil {
			return fmt.Errorf("workspace manager unavailable")
		}
		return m.manager.Commit()
	})
}

func (m *Manager) request(fn func() error) error {
	if m.post == nil {
		return fmt.Errorf("Wayland dispatcher unavailable")
	}
	done := make(chan error, 1)
	m.post(func() { done <- fn() })
	select {
	case err := <-done:
		return err
	case <-time.After(2 * time.Second):
		return fmt.Errorf("workspace request timed out")
	}
}

func (m *Manager) Close() {
	m.mu.Lock()
	manager := m.manager
	m.manager = nil
	m.available = false
	m.mu.Unlock()
	if manager != nil && m.post != nil {
		m.post(func() { _ = manager.Stop() })
	}
}
