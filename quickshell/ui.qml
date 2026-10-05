//@ pragma Env QSG_RENDER_LOOP=threaded
//@ pragma Env QT_MEDIA_BACKEND=ffmpeg
//@ pragma Env QT_FFMPEG_DECODING_HW_DEVICE_TYPES=vaapi
//@ pragma Env QT_FFMPEG_ENCODING_HW_DEVICE_TYPES=vaapi
//@ pragma Env QT_WAYLAND_DISABLE_WINDOWDECORATION=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Material
//@ pragma UseQApplication
//@ pragma AppId com.cytechteam.cyshell

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.CyCommon.Common as DC
import qs.Services

ShellRoot {
    id: root

    readonly property bool disableHotReload: Quickshell.env("CYSHELL_DISABLE_HOT_RELOAD") === "1" || Quickshell.env("CYSHELL_DISABLE_HOT_RELOAD") === "true"
    property bool uiLoaded: true

    Binding {
        target: Quickshell
        property: "watchFiles"
        value: !root.disableHotReload && !IdleService.isShellLocked
    }

    Component.onCompleted: {
        DC.Style.theme = Theme;
        DC.Style.settings = SettingsData;
        DC.I18n.backend = I18n;
        DC.Paths.backend = Paths;
        DC.Log.backend = Log;
        DC.Host.session = SessionService;
        DC.Host.cache = CacheData;

        // The shell UI owns transient desktop UX/polkit presentation, while
        // the Go core remains independent and survives UI restarts.
        void PolkitService.agent;
    }

    function refreshUi() {
        uiLoaded = false;
        uiReloadTimer.restart();
    }

    Timer {
        id: uiReloadTimer
        interval: 1
        repeat: false
        onTriggered: root.uiLoaded = true
    }

    Loader {
        active: root.uiLoaded
        asynchronous: false
        sourceComponent: CyShell {
            core: null
        }
    }

    IpcHandler {
        target: "shell-ui"

        function refresh(): string {
            root.refreshUi();
            return "SHELL_UI_REFRESHED";
        }
    }
}
