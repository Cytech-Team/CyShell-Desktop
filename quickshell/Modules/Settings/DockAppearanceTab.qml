import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Settings
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null

    readonly property var appsActiveColorOptions: [({
                "value": "primary",
                "label": I18n.tr("Primary")
            }), ({
                "value": "secondary",
                "label": I18n.tr("Secondary")
            }), ({
                "value": "primaryContainer",
                "label": I18n.tr("Primary Container")
            }), ({
                "value": "error",
                "label": I18n.tr("Error")
            }), ({
                "value": "success",
                "label": I18n.tr("Success", "noun, theme color name in active color dropdown")
            })]

    DockSelectionState {
        id: dock
    }

    SettingsPage {
        SettingsCard {
            width: parent.width
            visible: dock.hasConfig
            iconName: "photo_size_select_large"
            title: I18n.tr("Size")
            settingKey: "dockSizing"
            tags: ["dock", "size", "icon", "spacing", "padding", "margin", "thickness"]

            SettingsSliderRow {
                settingKey: "dockIconSize"
                tags: ["dock", "icon", "size", "scale"]
                resetStore: dock
                resetKeys: ["iconSize"]
                text: I18n.tr("Icon size")
                value: dock.config?.iconSize ?? 42
                minimum: 24
                maximum: 96
                unit: "px"
                onSliderValueChanged: value => dock.setOption("iconSize", value)
            }

            SettingsSliderRow {
                settingKey: "dockItemSpacing"
                tags: ["dock", "spacing", "icon", "widget", "gap"]
                resetStore: dock
                resetKeys: ["itemSpacing"]
                text: I18n.tr("Spacing", "slider label, gap between dock items")
                value: dock.config?.itemSpacing ?? 8
                minimum: 0
                maximum: 32
                unit: "px"
                onSliderValueChanged: value => dock.setOption("itemSpacing", value)
            }

            SettingsSliderRow {
                settingKey: "dockSpacing"
                tags: ["dock", "spacing", "padding"]
                resetStore: dock
                resetKeys: ["spacing"]
                text: I18n.tr("Padding", "noun, spacing setting label")
                value: dock.config?.spacing ?? 8
                minimum: 0
                maximum: 32
                unit: "px"
                onSliderValueChanged: value => dock.setOption("spacing", value)
            }

            SettingsSliderRow {
                settingKey: "dockMargin"
                tags: ["dock", "margin", "edge", "gap"]
                resetStore: dock
                resetKeys: ["margin"]
                text: I18n.tr("Margin", "slider label, gap between dock and screen edge")
                visible: !dock.connectedFrameModeActive
                value: dock.config?.margin ?? 8
                minimum: 0
                maximum: 100
                unit: "px"
                onSliderValueChanged: value => dock.setOption("margin", value)
            }
        }

        SettingsCard {
            width: parent.width
            visible: dock.hasConfig
            iconName: "apps"
            title: I18n.tr("Apps presentation")
            settingKey: "dockAppsPresentation"
            tags: ["dock", "apps", "icons", "indicator", "overflow", "hover"]

            SettingsRow {
                iconName: "dock_to_bottom"
                iconColor: Theme.primary
                title: I18n.tr("This standalone dock only")
                subtitle: I18n.tr("App visuals and capacity here do not change the CyBar taskbar")
            }

            SettingsSliderRow {
                resetStore: dock
                resetKeys: ["maxVisibleApps"]
                text: I18n.tr("Max pinned apps")
                minimumLabel: I18n.tr("All")
                value: dock.config?.maxVisibleApps ?? 0
                minimum: 0
                maximum: 30
                onSliderValueChanged: value => dock.setOption("maxVisibleApps", value)
            }

            SettingsSliderRow {
                resetStore: dock
                resetKeys: ["maxVisibleRunningApps"]
                text: I18n.tr("Max running apps")
                minimumLabel: I18n.tr("All")
                value: dock.config?.maxVisibleRunningApps ?? 0
                minimum: 0
                maximum: 30
                onSliderValueChanged: value => dock.setOption("maxVisibleRunningApps", value)
            }

            SettingsToggleRow {
                resetStore: dock
                resetKeys: ["showOverflowBadge"]
                text: I18n.tr("Overflow badge")
                checked: dock.config?.showOverflowBadge ?? true
                onToggled: checked => dock.setOption("showOverflowBadge", checked)
            }

            SettingsToggleRow {
                resetStore: dock
                resetKeys: ["appsDockHideIndicators"]
                text: I18n.tr("Indicators")
                checked: !(dock.config?.appsDockHideIndicators ?? false)
                onToggled: checked => dock.setOption("appsDockHideIndicators", !checked)
            }

            SettingsButtonGroupRow {
                resetStore: dock
                resetKeys: ["indicatorStyle"]
                readonly property var styles: ["circle", "line"]
                text: I18n.tr("Indicator style")
                enabled: !(dock.config?.appsDockHideIndicators ?? false)
                model: [I18n.tr("Circle", "dock indicator style option"), I18n.tr("Line", "dock indicator style option")]
                buttonPadding: Theme.spacingS
                currentIndex: Math.max(0, styles.indexOf(dock.config?.indicatorStyle ?? "circle"))
                onSelectionChanged: (index, selected) => {
                    if (selected)
                        dock.setOption("indicatorStyle", styles[index]);
                }
            }

            SettingsToggleRow {
                resetStore: dock
                resetKeys: ["appsDockColorizeActive"]
                text: I18n.tr("Colorize active")
                checked: dock.config?.appsDockColorizeActive ?? false
                onToggled: checked => dock.setOption("appsDockColorizeActive", checked)
            }

            ColorDropdownRow {
                resetStore: dock
                resetKeys: ["appsDockActiveColorMode"]
                text: I18n.tr("Active color")
                enabled: dock.config?.appsDockColorizeActive ?? false
                options: root.appsActiveColorOptions
                currentMode: dock.config?.appsDockActiveColorMode ?? "primary"
                onModeSelected: mode => dock.setOption("appsDockActiveColorMode", mode)
            }

            SettingsToggleRow {
                resetStore: dock
                resetKeys: ["appsDockEnlargeOnHover"]
                text: I18n.tr("Enlarge on hover")
                checked: dock.config?.appsDockEnlargeOnHover ?? false
                onToggled: checked => dock.setOption("appsDockEnlargeOnHover", checked)
            }

            SettingsSliderRow {
                resetStore: dock
                resetKeys: ["appsDockEnlargePercentage"]
                text: I18n.tr("Enlargement", "slider label, icon enlargement percent on hover")
                enabled: dock.config?.appsDockEnlargeOnHover ?? false
                value: dock.config?.appsDockEnlargePercentage ?? 125
                minimum: 100
                maximum: 150
                step: 5
                onSliderValueChanged: value => dock.setOption("appsDockEnlargePercentage", value)
            }
        }

        SettingsControlledBy {
            visible: dock.hasConfig && !dock.connectedFrameModeActive
            target: "surfaces"
            parentModal: root.parentModal
            section: "surfaceOpacity_dock_" + dock.selectedDockId
            settingLabel: I18n.tr("Opacity")
        }

        SettingsToggleCard {
            width: parent.width
            visible: dock.hasConfig && !dock.connectedFrameModeActive
            iconName: "border_style"
            settingKey: "dockBorder"
            tags: ["dock", "border", "outline"]
            resetStore: dock
            resetKeys: ["borderEnabled"]
            title: I18n.tr("Border")
            checked: dock.config?.borderEnabled ?? false
            onToggled: checked => dock.setOption("borderEnabled", checked)

            SettingsButtonGroupRow {
                resetStore: dock
                resetKeys: ["borderColor"]
                readonly property var colors: ["surfaceText", "secondary", "primary"]

                text: I18n.tr("Color", "noun, settings label for choosing a border, shadow or frame color")
                model: [I18n.tr("Surface", "color option"), I18n.tr("Secondary", "color option"), I18n.tr("Primary", "color option")]
                buttonPadding: Theme.spacingS
                minButtonWidth: 44
                textSize: Theme.fontSizeSmall
                currentIndex: Math.max(0, colors.indexOf(dock.config?.borderColor ?? "surfaceText"))
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    dock.setOption("borderColor", colors[index]);
                }
            }

            SettingsSliderRow {
                resetStore: dock
                resetKeys: ["borderOpacity"]
                text: I18n.tr("Opacity")
                value: Math.round((dock.config?.borderOpacity ?? 1) * 100)
                minimum: 0
                maximum: 100
                onSliderValueChanged: value => dock.setOption("borderOpacity", value / 100)
            }

            SettingsSliderRow {
                resetStore: dock
                resetKeys: ["borderThickness"]
                text: I18n.tr("Thickness", "slider label, border or outline width in pixels")
                value: dock.config?.borderThickness ?? 1
                minimum: 1
                maximum: 10
                unit: "px"
                onSliderValueChanged: value => dock.setOption("borderThickness", value)
            }
        }

        SettingsControlledBy {
            visible: dock.connectedFrameModeActive
            parentModal: root.parentModal
            section: "frameBorder"
            settingLabel: I18n.tr("Dock margin, opacity, and border")
            reason: I18n.tr("Managed by Frame in Connected Mode")
        }
    }
}
