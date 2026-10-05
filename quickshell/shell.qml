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
import qs.Common
import qs.Commons as NoctaliaCompatCommons
import qs.Services.UI as NoctaliaCompatUI
import qs.Services.System as NoctaliaCompatSystem
import qs.Modules.DesktopWidgets as NoctaliaCompatDesktopWidgets
import qs.Modules.Bar.Extras as NoctaliaCompatBarExtras
import qs.CyCommon.Common as DC
import qs.Modules
import qs.Services

ShellRoot {
    id: entrypoint

    readonly property bool runGreeter: Quickshell.env("CYSHELL_RUN_GREETER") === "1" || Quickshell.env("CYSHELL_RUN_GREETER") === "true"
    readonly property bool disableHotReload: Quickshell.env("CYSHELL_DISABLE_HOT_RELOAD") === "1" || Quickshell.env("CYSHELL_DISABLE_HOT_RELOAD") === "true"
    readonly property bool externalPanel: Quickshell.env("CYSHELL_EXTERNAL_PANEL") === "1"
    readonly property bool externalDesktop: Quickshell.env("CYSHELL_EXTERNAL_DESKTOP") === "1"

    Binding {
        target: Quickshell
        property: "watchFiles"
        value: !entrypoint.disableHotReload && (entrypoint.runGreeter || !IdleService.isShellLocked)
    }

    Component.onCompleted: {
        DC.Style.theme = Theme;
        DC.Style.settings = SettingsData;
        DC.I18n.backend = I18n;
        DC.Paths.backend = Paths;
        DC.Log.backend = Log;
        DC.Host.session = SessionService;
        DC.Host.cache = CacheData;
        if (entrypoint.runGreeter)
            return;
        // Build the polkit agent here, outside incubation: first-touching it from a Connections target during CyShell's async load crashed QQmlConnections::connectSignalsToMethods.
        void PolkitService.agent;
    }

    Loader {
        id: wallpaperLoader
        active: !entrypoint.runGreeter && !entrypoint.externalDesktop
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

    // Desktop icons are isolated from CyShell so an icon-provider failure
    // can never take down launcher/settings/popouts or the rest of the shell UI.
    Loader {
        id: desktopIconLayerLoader
        active: !entrypoint.runGreeter && !entrypoint.externalDesktop
        asynchronous: true
        source: "Modules/DesktopIconLayer.qml"
    }

    Loader {
        id: shellCoreLoader
        active: !entrypoint.runGreeter && !entrypoint.externalPanel
        asynchronous: true
        source: "ShellCore.qml"

        onLoaded: {
            if (cyShellLoader.item)
                cyShellLoader.item.core = item;
        }
    }

    Loader {
        id: cyShellLoader
        active: !entrypoint.runGreeter
        asynchronous: true
        source: "CyShell.qml"

        onLoaded: {
            if (shellCoreLoader.item)
                item.core = shellCoreLoader.item;
        }
    }

    Loader {
        id: dmsGreeterLoader
        active: entrypoint.runGreeter
        asynchronous: false
        source: "CyShellGreeter.qml"
    }
}
