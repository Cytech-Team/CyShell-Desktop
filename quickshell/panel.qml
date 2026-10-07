//@ pragma Env QSG_RENDER_LOOP=threaded
//@ pragma Env QT_WAYLAND_DISABLE_WINDOWDECORATION=1
//@ pragma AppId com.cytechteam.cyshell

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.CyCommon.Common as DC
import qs.Modules.Notifications.Center
import qs.Modules.Notifications.Popup
import qs.Services

ShellRoot {
    id: root

    readonly property var notificationPopupScreens: {
        const screens = SettingsData.notificationFocusedMonitor ? Quickshell.screens : SettingsData.getFilteredScreens("notifications");
        if (!SettingsData.dankIslandEnabled)
            return screens;
        return screens.filter(screen => !SettingsData.dankIslandHandlesNotifications(screen));
    }

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

    Variants {
        model: root.notificationPopupScreens

        delegate: NotificationPopupManager {}
    }

    // Notifications and their center must share this process: the panel owns
    // the freedesktop notification server and its unread state.
    LazyLoader {
        id: notificationCenterLoader
        active: false

        Component.onCompleted: {
            PopoutService.notificationCenterLoader = notificationCenterLoader;
        }

        NotificationCenterPopout {
            id: notificationCenter
            onPopoutClosed: PopoutService.unloadNotificationCenter()

            Component.onCompleted: {
                PopoutService.notificationCenterPopout = notificationCenter;
            }
        }
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

        function notificationCenter(action: string, payload: string): string {
            let request = ({});
            try {
                request = payload ? JSON.parse(payload) : ({});
            } catch (error) {
                return "NOTIFICATION_CENTER_INVALID_REQUEST";
            }

            if (action === "close") {
                PopoutService.invokeRemoteWidgetPopout("notificationCenter", "close", "notifications", 0, 0, 0, "center", null, "click", "", "notificationcenter", 0, 0, 0, null);
                return "NOTIFICATION_CENTER_CLOSED";
            }
            if (action !== "open" && action !== "toggle")
                return "NOTIFICATION_CENTER_INVALID_ACTION";

            const section = String(request.section || "center");
            const requestedScreen = String(request.screen || "");
            const screen = Quickshell.screens.find(candidate => candidate.name === requestedScreen) || Quickshell.screens[0] || null;
            if (!screen)
                return "NOTIFICATION_CENTER_NO_SCREEN";

            const fallback = BarWidgetService.naturalPopoutAnchor(screen, null, section);
            const hasTrigger = Number.isFinite(Number(request.x)) && Number.isFinite(Number(request.y)) && Number.isFinite(Number(request.width)) && Number(request.width) > 0;
            const trigger = hasTrigger ? request : fallback?.trigger;
            if (!trigger)
                return "NOTIFICATION_CENTER_NO_ANCHOR";

            const success = PopoutService.invokeRemoteWidgetPopout(
                "notificationCenter",
                action,
                String(request.triggerSource || "notifications"),
                Number(trigger.x),
                Number(trigger.y),
                Number(trigger.width),
                section,
                screen,
                request.mode === "hover" ? "hover" : "click",
                String(request.tab || ""),
                "notificationcenter",
                request.barPosition !== null && request.barPosition !== undefined && Number.isFinite(Number(request.barPosition)) ? Number(request.barPosition) : Number(fallback?.position ?? 0),
                request.barThickness !== null && request.barThickness !== undefined && Number.isFinite(Number(request.barThickness)) ? Number(request.barThickness) : Number(fallback?.thickness ?? 0),
                request.barSpacing !== null && request.barSpacing !== undefined && Number.isFinite(Number(request.barSpacing)) ? Number(request.barSpacing) : Number(fallback?.spacing ?? 0),
                request.barConfig && typeof request.barConfig === "object" ? request.barConfig : fallback?.config ?? null
            );
            return success ? "NOTIFICATION_CENTER_OPENED" : "NOTIFICATION_CENTER_FAILED";
        }

        function testNotifications(): string {
            NotificationService.sendTestNotifications();
            return "NOTIFICATION_TEST_STARTED";
        }
    }
}
