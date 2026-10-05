import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Settings.Widgets

Column {
    id: root

    required property string outputName
    required property var outputData

    readonly property bool isActive: outputData?.connected && outputData?.enabled
    readonly property bool isPrimary: DisplayConfigState.effectivePrimaryName === outputName
    readonly property bool isVirtual: DisplayConfigState.isVirtualOutput(outputData)

    width: parent?.width ?? 0
    spacing: Theme.spacingS

    SettingsCard {
        width: parent.width
        title: DisplayConfigState.getOutputDisplayName(root.outputData, root.outputName)

        SettingsRow {
            iconName: root.isVirtual ? "developer_board" : (root.isActive ? "desktop_windows" : "desktop_access_disabled")
            iconColor: root.isActive ? Theme.primary : Theme.surfaceVariantText
            title: root.isVirtual
                ? I18n.tr("Separate virtual desktop for Agent control")
                : ([root.outputData?.make, root.outputData?.model].filter(value => !!value).join(" · ") || root.outputName)
            subtitle: {
                const mode = DisplayConfigState.currentMode(root.outputData) || DisplayConfigState.preferredMode(root.outputData);
                const ppi = DisplayConfigState.estimatedPpi(root.outputName);
                let parts = [];
                if (mode)
                    parts.push(mode.width + "×" + mode.height + " @ " + DisplayConfigState.formatRefresh(mode.refresh));
                if (root.outputData?.physicalWidth > 0 && root.outputData?.physicalHeight > 0)
                    parts.push(root.outputData.physicalWidth + "×" + root.outputData.physicalHeight + " mm");
                if (ppi > 0)
                    parts.push("~" + ppi + " PPI");
                return parts.join(" · ");
            }
            trailingBadge: root.isPrimary
                ? I18n.tr("Main display")
                : (root.isVirtual ? I18n.tr("Agent Workspace") : "")
        }

        SettingsToggleRow {
            text: root.isVirtual ? I18n.tr("Enable Agent Workspace") : I18n.tr("Use this display")
            checked: root.outputData?.enabled ?? false
            enabled: checked ? DisplayConfigState.canDisableOutput(root.outputName) : true
            onToggled: checked => DisplayConfigState.setPendingChange(root.outputName, "enabled", checked)
        }

        SettingsDropdownRow {
            visible: root.isActive
            text: I18n.tr("Resolution")
            options: DisplayConfigState.resolutionOptions(root.outputName)
            currentValue: DisplayConfigState.formatResolution(
                DisplayConfigState.currentMode(root.outputData) || DisplayConfigState.preferredMode(root.outputData)
            )
            onValueChanged: value => {
                const modeId = DisplayConfigState.modeIdForResolution(root.outputName, value);
                if (modeId !== undefined)
                    DisplayConfigState.setPendingChange(root.outputName, "modeId", modeId);
            }
        }

        SettingsDropdownRow {
            visible: root.isActive
            text: I18n.tr("Refresh rate")
            description: I18n.tr("Frames per second supported by this display mode (Hz)")
            options: DisplayConfigState.refreshOptions(root.outputName)
            currentValue: {
                const mode = DisplayConfigState.currentMode(root.outputData) || DisplayConfigState.preferredMode(root.outputData);
                return mode ? DisplayConfigState.formatRefresh(mode.refresh) : "";
            }
            onValueChanged: value => {
                const modeId = DisplayConfigState.modeIdForRefresh(root.outputName, value);
                if (modeId !== undefined)
                    DisplayConfigState.setPendingChange(root.outputName, "modeId", modeId);
            }
        }

        SettingsDropdownRow {
            visible: root.isActive
            text: I18n.tr("Scale")
            description: I18n.tr("Wayland display scaling (DPI/UI size)")
            options: DisplayConfigState.scaleOptions(root.outputName)
            currentValue: DisplayConfigState.formatScale(root.outputData?.logical?.scale || 1)
            onValueChanged: value => {
                const scale = DisplayConfigState.scaleForLabel(value);
                if (!isNaN(scale) && scale > 0)
                    DisplayConfigState.setPendingChange(root.outputName, "scale", scale);
            }
        }

        SettingsRow {
            visible: root.isActive
            title: I18n.tr("Position")
            subtitle: I18n.tr("Logical desktop coordinates; you can also drag the display above")

            Row {
                spacing: Theme.spacingS

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "X"
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }

                DankTextField {
                    id: xField
                    width: 92
                    outlined: true
                    placeholderText: "0"
                    onAccepted: {
                        const value = parseInt(text);
                        if (!isNaN(value))
                            DisplayConfigState.updatePosition(root.outputName, value, root.outputData?.logical?.y ?? 0);
                    }
                    onEditingFinished: {
                        if (activeFocus)
                            return;
                        const value = parseInt(text);
                        if (!isNaN(value))
                            DisplayConfigState.updatePosition(root.outputName, value, root.outputData?.logical?.y ?? 0);
                    }
                }

                Binding {
                    target: xField
                    property: "text"
                    value: String(root.outputData?.logical?.x ?? 0)
                    when: !xField.activeFocus
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Y"
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }

                DankTextField {
                    id: yField
                    width: 92
                    outlined: true
                    placeholderText: "0"
                    onAccepted: {
                        const value = parseInt(text);
                        if (!isNaN(value))
                            DisplayConfigState.updatePosition(root.outputName, root.outputData?.logical?.x ?? 0, value);
                    }
                    onEditingFinished: {
                        if (activeFocus)
                            return;
                        const value = parseInt(text);
                        if (!isNaN(value))
                            DisplayConfigState.updatePosition(root.outputName, root.outputData?.logical?.x ?? 0, value);
                    }
                }

                Binding {
                    target: yField
                    property: "text"
                    value: String(root.outputData?.logical?.y ?? 0)
                    when: !yField.activeFocus
                }
            }
        }

        SettingsDropdownRow {
            visible: root.isActive
            text: I18n.tr("Orientation")
            options: [
                I18n.tr("Normal"),
                "90°",
                "180°",
                "270°",
                I18n.tr("Flipped"),
                I18n.tr("Flipped 90°"),
                I18n.tr("Flipped 180°"),
                I18n.tr("Flipped 270°")
            ]
            currentValue: DisplayConfigState.getTransformLabel(root.outputData?.logical?.transform ?? 0)
            onValueChanged: value => DisplayConfigState.setPendingChange(
                root.outputName,
                "transform",
                DisplayConfigState.getTransformValue(value)
            )
        }

        SettingsToggleRow {
            visible: root.isActive && (root.outputData?.vrr_supported ?? false)
            text: I18n.tr("Variable refresh rate (VRR)")
            description: I18n.tr("Adaptive Sync when supported by the monitor and GPU")
            checked: root.outputData?.vrr_enabled ?? false
            onToggled: checked => DisplayConfigState.setPendingChange(root.outputName, "vrr", checked)
        }

        SettingsRow {
            visible: root.isActive && !root.isPrimary && !root.isVirtual
            title: I18n.tr("Main display")
            subtitle: I18n.tr("Use this screen as CyShell's default display")

            DankButton {
                text: I18n.tr("Make main")
                iconName: "star"
                onClicked: DisplayConfigState.setPrimaryDisplay(root.outputName)
            }
        }
    }
}
