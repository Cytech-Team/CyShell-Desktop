//@ pragma Env QSG_RENDER_LOOP=threaded
//@ pragma Env QT_WAYLAND_DISABLE_WINDOWDECORATION=1
//@ pragma AppId com.cytechteam.cyshell

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.CyCommon.Common as DC
import qs.Modules
import qs.Modules.DesktopWidgets
import qs.Services

ShellRoot {
    id: root

    property bool surfacesLoaded: true

    Component.onCompleted: {
        DC.Style.theme = Theme;
        DC.Style.settings = SettingsData;
        DC.I18n.backend = I18n;
        DC.Paths.backend = Paths;
        DC.Log.backend = Log;
        DC.Host.session = SessionService;
        DC.Host.cache = CacheData;
    }

    function refreshDesktop() {
        surfacesLoaded = false;
        reloadTimer.restart();
    }

    Timer {
        id: reloadTimer
        interval: 1
        repeat: false
        onTriggered: root.surfacesLoaded = true
    }

    Loader {
        active: root.surfacesLoaded
        asynchronous: false
        sourceComponent: Scope {
            WallpaperBackground {}

            Loader {
                active: SettingsData.blurredWallpaperLayer && CompositorService.isNiri
                asynchronous: false
                sourceComponent: BlurredWallpaperBackground {}
            }
        }
    }

    Loader {
        id: iconLayerLoader
        active: root.surfacesLoaded
        asynchronous: false
        sourceComponent: DesktopIconLayer {}
    }

    Loader {
        active: root.surfacesLoaded
        asynchronous: false
        sourceComponent: DesktopWidgetLayer {}
    }

    IpcHandler {
        target: "desktop"

        function refresh(): string {
            root.refreshDesktop();
            return "DESKTOP_REFRESHED";
        }

        function wallpaperState(): string {
            const screens = {};
            for (const screen of Quickshell.screens)
                screens[screen.name] = SessionData.getMonitorWallpaper(screen.name) || "";
            return JSON.stringify({
                wallpaperPath: SessionData.wallpaperPath || "",
                perMonitor: SessionData.perMonitorWallpaper,
                screens
            });
        }

        function iconState(): string {
            return JSON.stringify(iconLayerLoader.item?.debugState?.() || []);
        }
    }
}
