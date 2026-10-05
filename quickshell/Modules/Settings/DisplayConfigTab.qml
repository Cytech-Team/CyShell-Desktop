import QtQuick
import qs.Common
import qs.Modals
import qs.Services
import qs.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.Settings.DisplayConfig

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var parentModal: null

    Connections {
        target: DisplayConfigState

        function onChangesApplied(changeDescriptions) {
            confirmationModal.changes = changeDescriptions;
            confirmationModal.open();
        }

        function onApplyFailed(message) {
            ToastService.showError(I18n.tr("Display configuration failed"), message);
        }

        function onChangesConfirmed() {
            ToastService.showInfo(I18n.tr("Display settings saved"));
        }

        function onChangesReverted() {
            ToastService.showInfo(I18n.tr("Display settings reverted"));
        }
    }

    SettingsPage {
        id: page

        SettingsCard {
            width: parent.width
            iconName: "monitor"
            title: I18n.tr("Display layout")

            SettingsDropdownRow {
                text: I18n.tr("Main display")
                description: I18n.tr("Default screen for CyShell desktop surfaces and global shell actions")
                options: DisplayConfigState.primaryOptions
                currentValue: {
                    const name = DisplayConfigState.effectivePrimaryName;
                    return name
                        ? DisplayConfigState.getOutputDisplayName(DisplayConfigState.allOutputs[name], name)
                        : "";
                }
                onValueChanged: value => {
                    const name = DisplayConfigState.outputNameForDisplayLabel(value);
                    if (name)
                        DisplayConfigState.setPrimaryDisplay(name);
                }
            }

            SettingsToggleRow {
                settingKey: "displaySnapToEdge"
                text: I18n.tr("Snap displays while dragging")
                checked: SettingsData.displaySnapToEdge
                onToggled: checked => {
                    SettingsData.displaySnapToEdge = checked;
                    SettingsData.saveSettings();
                }
            }

            SettingsToggleRow {
                settingKey: "displayAutoPrimaryOnLidClose"
                visible: LaptopLidService.lidPresent || LaptopLidService.internalOutputName !== ""
                text: I18n.tr("Move main display when laptop lid closes")
                description: I18n.tr("If the internal panel is the main display, CyShell switches to an enabled external display and can restore the laptop panel when the lid opens")
                checked: SettingsData.displayAutoPrimaryOnLidClose
                onToggled: checked => {
                    SettingsData.set("displayAutoPrimaryOnLidClose", checked);
                    SettingsData.saveSettings();
                }
            }

            SettingsToggleRow {
                settingKey: "displayRestorePrimaryOnLidOpen"
                visible: SettingsData.displayAutoPrimaryOnLidClose
                    && (LaptopLidService.lidPresent || LaptopLidService.internalOutputName !== "")
                text: I18n.tr("Restore laptop display when lid opens")
                checked: SettingsData.displayRestorePrimaryOnLidOpen
                onToggled: checked => {
                    SettingsData.set("displayRestorePrimaryOnLidOpen", checked);
                    SettingsData.saveSettings();
                }
            }

            MonitorCanvas {
                width: parent.width
            }
        }

        Repeater {
            model: Object.keys(DisplayConfigState.allOutputs || {}).filter(name =>
                !DisplayConfigState.isVirtualOutput(DisplayConfigState.allOutputs[name])
            )

            delegate: OutputCard {
                required property string modelData
                outputName: modelData
                outputData: DisplayConfigState.allOutputs[modelData]
            }
        }

        SettingsCard {
            width: parent.width
            visible: Object.keys(DisplayConfigState.allOutputs || {}).some(name =>
                DisplayConfigState.isVirtualOutput(DisplayConfigState.allOutputs[name])
            )
            iconName: "smart_toy"
            title: I18n.tr("Agent Workspace")

            SettingsRow {
                title: I18n.tr("Agent Workspace is managed in Agent")
                subtitle: I18n.tr("The optional Agent Workspace virtual desktop is managed in Agent settings instead of normal physical displays")
                iconName: "developer_board"

                DankButton {
                    text: I18n.tr("Open Agent")
                    iconName: "smart_toy"
                    onClicked: {
                        if (root.parentModal)
                            root.parentModal.navigateTo("agent");
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            visible: DisplayConfigState.hasPendingChanges

            SettingsRow {
                title: I18n.tr("Unsaved display changes")
                subtitle: I18n.tr("Changes are tested first. After applying, confirm within 10 seconds or the old layout is restored.")

                Row {
                    spacing: Theme.spacingS

                    DankButton {
                        text: I18n.tr("Discard")
                        backgroundColor: "transparent"
                        textColor: Theme.surfaceText
                        enabled: !DisplayConfigState.applying
                        onClicked: DisplayConfigState.discardChanges()
                    }

                    DankButton {
                        text: DisplayConfigState.applying ? I18n.tr("Applying…") : I18n.tr("Apply changes")
                        iconName: "check"
                        enabled: !DisplayConfigState.applying
                        onClicked: DisplayConfigState.applyChanges()
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            visible: !DisplayConfigState.hasOutputBackend
            iconName: "warning"
            title: I18n.tr("Display management unavailable")

            SettingsRow {
                subtitle: I18n.tr("CyShell could not connect to Labwc's wlr-output-management backend.")
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "info"
            title: I18n.tr("About display scaling")

            SettingsRow {
                subtitle: I18n.tr("Scale controls Wayland UI size. 100% means scale 1.0; 125% means 1.25. The PPI value shown above is an estimate from the monitor's physical size and selected resolution.")
            }
        }
    }

    DisplayConfirmationModal {
        id: confirmationModal

        onConfirmed: DisplayConfigState.confirmChanges()
        onReverted: DisplayConfigState.revertChanges()
    }
}
