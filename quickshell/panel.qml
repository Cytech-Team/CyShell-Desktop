//@ pragma Env QSG_RENDER_LOOP=threaded
//@ pragma Env QT_WAYLAND_DISABLE_WINDOWDECORATION=1
//@ pragma AppId com.cytechteam.cyshell

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.CyCommon.Common as DC
import qs.Services

ShellRoot {
    id: root

    Component.onCompleted: {
        DC.Style.theme = Theme;
        DC.Style.settings = SettingsData;
        DC.I18n.backend = I18n;
        DC.Paths.backend = Paths;
        DC.Log.backend = Log;
        DC.Host.session = SessionService;
        DC.Host.cache = CacheData;
    }

    ShellCore {
        id: core
    }

    PanelIPC {}

    IpcHandler {
        target: "panel"

        function refresh(): string {
            core.recreateBarSurfaces();
            return "PANEL_REFRESHED";
        }

        function recover(): string {
            core.triggerSurfaceRecovery("ipc");
            return "PANEL_RECOVERY_SCHEDULED";
        }
    }
}
