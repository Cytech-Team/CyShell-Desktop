pragma ComponentBehavior: Bound
import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import qs.Modules.Dock
import qs.Modules.SurfaceWidgets
import qs.Common.settings
import "../../../Common/settings/DockConfig.js" as DockConfig

BasePill {
    id: root
    property var surfaceContext: null
    property var widgetData: null
    property var topBar: null
    property bool isAutoHideBar: false
    readonly property bool dockHosted: surfaceContext?.kind === "dock"
    readonly property bool barHasCyStart: {
        if (dockHosted || !barConfig)
            return false;
        const groups = [barConfig.leftWidgets || [], barConfig.centerWidgets || [], barConfig.rightWidgets || []];
        for (const group of groups) {
            for (const entry of group) {
                const id = typeof entry === "string" ? entry : (entry?.id || entry?.widgetId || "");
                if (id === "cyStart" && (typeof entry === "string" || entry?.enabled !== false))
                    return true;
            }
        }
        return false;
    }
    function appOption(key, fallback) {
        if (!dockHosted)
            return SettingsData.widgetOption("appsDock", widgetData, key);
        return widgetData?.[key] ?? fallback;
    }
    function appBehaviorOption(key, fallback) {
        if (dockHosted)
            return widgetData?.options?.[key] ?? fallback;
        return SettingsData.appsDockSharedOption(key, fallback);
    }
    // A dock reads strip options from its own configuration; a bar keeps per-instance copies.
    readonly property var appOptions: {
        const defaults = DockConfig.create("", "");
        const options = dockHosted ? Object.assign(defaults, surfaceContext.config, widgetData?.options ?? {}) : Object.assign(defaults, {
            position: barConfig?.position ?? 0,
            iconSize: Theme.barIconSize(barThickness, undefined, barConfig?.maximizeWidgetIcons, barConfig?.iconScale),
            itemSpacing: appOption("appsDockSpacing", 4),
            maxVisibleApps: appOption("barMaxVisibleApps", defaults.maxVisibleApps),
            maxVisibleRunningApps: appOption("barMaxVisibleRunningApps", defaults.maxVisibleRunningApps),
            showOverflowBadge: appOption("barShowOverflowBadge", defaults.showOverflowBadge)
        });
        return Object.assign(options, {
            // Dock behavior lives with its Apps widget; CyBar keeps its shared taskbar settings.
            groupByApp: appBehaviorOption("groupByApp", true),
            separatePinnedAndRunningApps: appBehaviorOption("separatePinnedAndRunningApps", false),
            currentWorkspace: appBehaviorOption("currentWorkspace", false),
            restoreSpecialWorkspaceOnClick: appBehaviorOption("restoreSpecialWorkspaceOnClick", false),
            iconSize: Math.min(options.iconSize, surfaceContext?.widgetThickness ?? options.iconSize),
            compact: dockHosted || appOption("runningAppsCompactMode", true),
            hideIndicators: dockHosted ? (surfaceContext?.config?.appsDockHideIndicators ?? false) : appOption("appsDockHideIndicators", false),
            indicatorStyle: dockHosted ? (surfaceContext?.config?.indicatorStyle ?? "circle") : appOption("appsDockIndicatorStyle", (barConfig?.widgetStyle ?? "pills") === "taskbar" ? "taskbar" : "line"),
            taskbarVisuals: !dockHosted && (barConfig?.widgetStyle ?? "pills") === "taskbar",
            colorizeActive: dockHosted ? (surfaceContext?.config?.appsDockColorizeActive ?? false) : appOption("appsDockColorizeActive", false),
            activeColorMode: dockHosted ? (surfaceContext?.config?.appsDockActiveColorMode ?? "primary") : appOption("appsDockActiveColorMode", "primary"),
            enlargeOnHover: dockHosted ? (surfaceContext?.config?.appsDockEnlargeOnHover ?? false) : appOption("appsDockEnlargeOnHover", false),
            enlargePercentage: dockHosted ? (surfaceContext?.config?.appsDockEnlargePercentage ?? 125) : appOption("appsDockEnlargePercentage", 125),
            // Standalone Dock owns its absolute icon size; CyBar keeps an Apps-only scale.
            iconSizePercentage: dockHosted ? 100 : appOption("appsDockIconSizePercentage", 100),
            // CyStart is the taskbar launcher. Do not render the legacy 9-dot
            // Applications button beside it; keep that launcher for standalone Dock.
            launcherEnabled: dockHosted ? options.launcherEnabled : (barHasCyStart ? false : options.launcherEnabled)
        });
    }
    property bool renderItems: true
    property var mixedStrip: null
    property var stripItem: null
    function focusFirst() {
        stripItem?.focusFirst();
    }
    readonly property bool interactionActive: appMenu.visible || trashMenu.visible || (stripItem?.requestDockShow ?? false) || (stripItem?.draggedIndex ?? -1) >= 0 || (stripItem?.previewInteractionActive ?? false)
    readonly property var hoveredButton: stripItem?.hoveredButton ?? null
    enableBackgroundHover: false
    enableCursor: false
    // Dock apps sit straight on the dock surface; a widget pill around them would read as a second dock.
    noBackground: dockHosted || (barConfig?.noBackground ?? false)

    content: Component {
        ApplicationStrip {
            id: apps
            renderItems: root.renderItems
            mixedStrip: root.mixedStrip
            surfaceContext: root.surfaceContext
            options: root.appOptions
            dockScreen: root.parentScreen
            isVertical: root.isVerticalOrientation
            iconSize: root.appOptions.iconSize
            groupByApp: root.appOptions.groupByApp
            usesOverlayLayer: root.surfaceContext?.host?.usesOverlayLayer ?? false
            contextMenu: appMenu
            trashContextMenu: trashMenu
            Component.onCompleted: root.stripItem = apps
        }
    }
    DockContextMenu {
        id: appMenu
        options: root.appOptions
    }
    DockTrashContextMenu {
        id: trashMenu
        options: root.appOptions
    }
}
