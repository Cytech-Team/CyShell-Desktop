package extworkspace

import (
	"fmt"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/server/models"
	"github.com/AvengeMedia/dankgo/ipc"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	if manager == nil {
		models.RespondError(conn, req.ID, "workspace manager not initialized")
		return
	}
	switch req.Method {
	case "workspace.getState":
		models.Respond(conn, req.ID, manager.GetState())
	case "workspace.activate":
		selector, ok := models.Get[string](req, "workspace")
		if !ok || selector == "" {
			models.RespondError(conn, req.ID, "workspace is required")
			return
		}
		if err := manager.Activate(selector); err != nil {
			models.RespondError(conn, req.ID, err.Error())
			return
		}
		models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: fmt.Sprintf("workspace %s activation requested", selector)})
	default:
		models.RespondError(conn, req.ID, fmt.Sprintf("unknown workspace method: %s", req.Method))
	}
}
