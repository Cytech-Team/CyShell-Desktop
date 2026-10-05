package lyrics

import (
	"context"
	"fmt"
	"path/filepath"
	"time"

	"github.com/AvengeMedia/dankgo/ipc"
	"github.com/AvengeMedia/dankgo/ipc/params"
	corelyrics "github.com/AvengeMedia/dankgo/lyrics"
	"github.com/Cytech-Team/CyShell-Desktop/core/internal/server/models"
	"github.com/Cytech-Team/CyShell-Desktop/core/internal/utils"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request) {
	switch req.Method {
	case "lyrics.get":
		handleGet(conn, req)
	default:
		models.RespondError(conn, req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

var client = corelyrics.New(corelyrics.Options{
	CacheDir:  filepath.Join(utils.XDGCacheHome(), "CyShell", "lyrics"),
	UserAgent: "CyShell/1 (+https://github.com/Cytech-Team/CyShell-Desktop)",
})

func handleGet(conn *ipc.ConnWriter, req ipc.Request) {
	var providers []corelyrics.Provider
	if _, configured := req.Params["providers"]; configured {
		providers = []corelyrics.Provider{}
		for _, id := range params.StringSlice(req.Params, "providers") {
			providers = append(providers, corelyrics.Provider(id))
		}
	}
	result, err := client.Lookup(context.Background(), corelyrics.Request{
		Title:     params.StringOpt(req.Params, "title", ""),
		Artist:    params.StringOpt(req.Params, "artist", ""),
		Album:     params.StringOpt(req.Params, "album", ""),
		Duration:  time.Duration(params.IntOpt(req.Params, "duration", 0)) * time.Second,
		FileURL:   params.StringOpt(req.Params, "fileUrl", ""),
		CacheOnly: !params.BoolOpt(req.Params, "allowNetwork", false),
		Providers: providers,
	})
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	models.Respond(conn, req.ID, result)
	client.Prune()
}
