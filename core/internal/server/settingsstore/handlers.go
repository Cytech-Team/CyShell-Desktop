package settingsstore

import (
	"github.com/AvengeMedia/dankgo/ipc"
	"github.com/Cytech-Team/CyShell-Desktop/core/internal/server/models"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	switch req.Method {
	case "settings.get":
		models.Respond(conn, req.ID, manager.Snapshot())
	case "settings.replace":
		kind, _ := models.Get[string](req, "kind")
		raw, ok := models.Get[string](req, "json")
		if !ok || raw == "" {
			models.RespondError(conn, req.ID, "json is required")
			return
		}
		state, err := manager.Replace(kind, raw)
		if err != nil {
			models.RespondError(conn, req.ID, err.Error())
			return
		}
		models.Respond(conn, req.ID, state)
	default:
		models.RespondError(conn, req.ID, "unknown settings method: "+req.Method)
	}
}
