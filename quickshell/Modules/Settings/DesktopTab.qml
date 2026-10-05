import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null

    function layoutLabel(mode) {
        return String(mode || "grid") === "free" ? I18n.tr("Free") : I18n.tr("Grid");
    }

    function layoutMode(label) {
        return label === I18n.tr("Free") ? "free" : "grid";
    }

    function edgeActionLabel(action) {
        switch (String(action || "none")) {
        case "launcher": return I18n.tr("Launcher");
        case "control-center": return I18n.tr("Control Center");
        case "settings": return I18n.tr("Settings");
        case "process-list": return I18n.tr("Process List");
        default: return I18n.tr("None");
        }
    }

    function edgeActionValue(label) {
        if (label === I18n.tr("Launcher")) return "launcher";
        if (label === I18n.tr("Control Center")) return "control-center";
        if (label === I18n.tr("Settings")) return "settings";
        if (label === I18n.tr("Process List")) return "process-list";
        return "none";
    }

    SettingsPage {
        id: page

        SettingsCard {
            width: parent.width
            title: I18n.tr("Desktop icons")
            iconName: "grid_view"
            settingKey: "desktopIconLayoutMode"
            tags: ["desktop", "icons", "grid", "free", "arrange", "layout"]

            SettingsDropdownRow {
                text: I18n.tr("Icon layout")
                description: I18n.tr("Grid aligns icons to fixed cells and prevents overlaps. Free keeps exact drag positions.")
                options: [I18n.tr("Grid"), I18n.tr("Free")]
                currentValue: root.layoutLabel(SettingsData.desktopIconLayoutMode)
                onValueChanged: value => {
                    const mode = root.layoutMode(value);
                    if (mode === SettingsData.desktopIconLayoutMode)
                        return;
                    SettingsData.set("desktopIconLayoutMode", mode);
                    SettingsData.saveSettings();
                }
            }

            SettingsRow {
                title: SettingsData.desktopIconLayoutMode === "grid"
                    ? I18n.tr("Grid placement")
                    : I18n.tr("Free placement")
                subtitle: SettingsData.desktopIconLayoutMode === "grid"
                    ? I18n.tr("Dragging snaps to the nearest available desktop cell. Existing saved positions are resolved deterministically so icons do not stack on top of each other.")
                    : I18n.tr("Icons can be placed anywhere on the desktop and keep their saved pixel positions.")
                iconName: SettingsData.desktopIconLayoutMode === "grid" ? "grid_4x4" : "open_with"
                iconColor: Theme.primary
            }

            SettingsRow {
                title: I18n.tr("Reset icon positions")
                subtitle: I18n.tr("Clear saved positions and arrange desktop items from the top-left again.")
                iconName: "restart_alt"

                CyButton {
                    text: I18n.tr("Reset")
                    iconName: "restart_alt"
                    onClicked: {
                        SettingsData.set("desktopIconPositions", {});
                        SettingsData.saveSettings();
                        ToastService.showInfo(I18n.tr("Desktop icon positions reset"));
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            title: I18n.tr("CyShell LabWC integration")
            iconName: "desktop_windows"
            settingKey: "screenEdgesEnabled"
            tags: ["labwc", "screen", "edge", "hot", "corner", "window", "switcher", "cyshell"]

            SettingsRow {
                title: I18n.tr("LabWC backend")
                subtitle: CompositorService.isLabwc
                    ? I18n.tr("CyShell is using the custom LabWC backend installed on this system. CyShell owns the integration layer; LabWC itself is left untouched.")
                    : I18n.tr("These features are designed for the CyShell LabWC session and remain compositor-independent where possible.")
                iconName: CompositorService.isLabwc ? "check_circle" : "info"
                iconColor: CompositorService.isLabwc ? Theme.primary : Theme.surfaceVariantText

                CyButton {
                    visible: CompositorService.isLabwc
                    text: I18n.tr("Reconfigure")
                    iconName: "refresh"
                    onClicked: LabwcService.reconfigure()
                }
            }

            SettingsToggleRow {
                settingKey: "screenEdgesEnabled"
                text: I18n.tr("Screen edges")
                description: I18n.tr("Run CyShell edge triggers in the independent UI-surfaces process so they survive a main shell restart.")
                checked: SettingsData.screenEdgesEnabled
                onToggled: checked => SettingsData.set("screenEdgesEnabled", checked)
            }

            SettingsSliderRow {
                settingKey: "screenEdgeThickness"
                text: I18n.tr("Edge activation width")
                value: SettingsData.screenEdgeThickness
                unit: " px"
                minimum: 1
                maximum: 12
                step: 1
                enabled: SettingsData.screenEdgesEnabled
                onSliderValueChanged: newValue => SettingsData.set("screenEdgeThickness", Math.round(newValue))
            }

            SettingsDropdownRow {
                settingKey: "screenEdgeLeftAction"
                text: I18n.tr("Left edge")
                options: [I18n.tr("None"), I18n.tr("Launcher"), I18n.tr("Control Center"), I18n.tr("Settings"), I18n.tr("Process List")]
                currentValue: root.edgeActionLabel(SettingsData.screenEdgeLeftAction)
                enabled: SettingsData.screenEdgesEnabled
                onValueChanged: value => SettingsData.set("screenEdgeLeftAction", root.edgeActionValue(value))
            }

            SettingsDropdownRow {
                settingKey: "screenEdgeRightAction"
                text: I18n.tr("Right edge")
                options: [I18n.tr("None"), I18n.tr("Launcher"), I18n.tr("Control Center"), I18n.tr("Settings"), I18n.tr("Process List")]
                currentValue: root.edgeActionLabel(SettingsData.screenEdgeRightAction)
                enabled: SettingsData.screenEdgesEnabled
                onValueChanged: value => SettingsData.set("screenEdgeRightAction", root.edgeActionValue(value))
            }

            SettingsDropdownRow {
                settingKey: "screenEdgeTopAction"
                text: I18n.tr("Top edge")
                options: [I18n.tr("None"), I18n.tr("Launcher"), I18n.tr("Control Center"), I18n.tr("Settings"), I18n.tr("Process List")]
                currentValue: root.edgeActionLabel(SettingsData.screenEdgeTopAction)
                enabled: SettingsData.screenEdgesEnabled
                onValueChanged: value => SettingsData.set("screenEdgeTopAction", root.edgeActionValue(value))
            }

            SettingsDropdownRow {
                settingKey: "screenEdgeBottomAction"
                text: I18n.tr("Bottom edge")
                options: [I18n.tr("None"), I18n.tr("Launcher"), I18n.tr("Control Center"), I18n.tr("Settings"), I18n.tr("Process List")]
                currentValue: root.edgeActionLabel(SettingsData.screenEdgeBottomAction)
                enabled: SettingsData.screenEdgesEnabled
                onValueChanged: value => SettingsData.set("screenEdgeBottomAction", root.edgeActionValue(value))
            }
        }
    }
}
