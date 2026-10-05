import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Settings
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var page: null
    readonly property var apps: page?.appStore ?? null

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsCard {
        iconName: "apps"
        title: I18n.tr("Apps behavior")
        settingKey: "appsDockSharedBehavior"

        SettingsRow {
            iconName: root.page?.dockHosted ? "dock_to_bottom" : "sync"
            iconColor: Theme.primary
            title: root.page?.dockHosted ? I18n.tr("Dock-specific Apps behavior") : I18n.tr("Shared Apps behavior")
            subtitle: root.page?.dockHosted ? I18n.tr("Pinned apps and behavior are saved separately for this Dock") : I18n.tr("CyBar Apps behavior is shared with the taskbar")
        }

        SettingsToggleRow {
            resetStore: root.apps
            resetKeys: ["currentWorkspace"]
            text: I18n.tr("Current workspace", "Running apps filter: only show apps from the active workspace")
            checked: root.apps?.get("currentWorkspace") ?? false
            onToggled: checked => root.apps?.set("currentWorkspace", checked)
        }

        SettingsToggleRow {
            resetStore: root.apps
            resetKeys: ["groupByApp"]
            text: I18n.tr("Group by app")
            checked: root.apps?.get("groupByApp") ?? true
            onToggled: checked => root.apps?.set("groupByApp", checked)
        }

        SettingsToggleRow {
            resetStore: root.apps
            resetKeys: ["separatePinnedAndRunningApps"]
            text: I18n.tr("Separate pinned and running apps")
            checked: root.apps?.get("separatePinnedAndRunningApps") ?? false
            onToggled: checked => root.apps?.set("separatePinnedAndRunningApps", checked)
        }

        SettingsToggleRow {
            visible: CompositorService.isHyprland
            resetStore: root.apps
            resetKeys: ["restoreSpecialWorkspaceOnClick"]
            text: I18n.tr("Restore special workspace")
            checked: root.apps?.get("restoreSpecialWorkspaceOnClick") ?? false
            onToggled: checked => root.apps?.set("restoreSpecialWorkspaceOnClick", checked)
        }
    }

    SettingsCard {
        iconName: "palette"
        title: I18n.tr("Surface appearance")
        settingKey: "appsDockSurfaceHint"

        SettingsRow {
            iconName: "info"
            iconColor: Theme.surfaceVariantText
            title: I18n.tr("Configured per surface")
            subtitle: I18n.tr("Position, auto-hide, opacity, icon size, spacing and indicators belong to the CyBar or Standalone Dock appearance settings")
        }
    }
}
