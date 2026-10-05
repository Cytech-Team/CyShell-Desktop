package evdev

import (
	"github.com/AvengeMedia/dankgo/ipc"
	"github.com/Cytech-Team/CyShell-Desktop/core/internal/server/models"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	switch req.Method {
	case "evdev.getState":
		handleGetState(conn, req, m)
	default:
		models.RespondError(conn, req.ID, "unknown method: "+req.Method)
	}
}

func handleGetState(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	models.Respond(conn, req.ID, m.GetState())
}
