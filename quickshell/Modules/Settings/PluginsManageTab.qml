pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Settings.Widgets

FocusScope {
    id: root

    property string registryError: ""
    property bool registryBusy: false
    focus: true

    function refreshRegistries() {
        if (!CyShellService.backendAvailable || CyShellService.apiVersion < 29)
            return;
        registryBusy = true;
        registryError = "";
        CyShellService.listRegistries(response => {
            registryBusy = false;
            registryError = response.error || "";
        });
    }

    Component.onCompleted: {
        if (CyShellService.backendAvailable && CyShellService.apiVersion >= 29)
            root.refreshRegistries();
    }

    Connections {
        target: CyShellService

        function onBackendAvailableChanged() {
            if (CyShellService.backendAvailable && CyShellService.apiVersion >= 29)
                root.refreshRegistries();
        }
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            iconName: "folder"
            title: I18n.tr("Directory", "plugin settings card title, folder where plugins are placed")
            settingKey: "pluginDirectory"
            tags: ["plugins", "directory", "folder", "path"]

            SettingsRow {
                body: StyledText {
                    text: PluginService.pluginDirectory
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    font.family: "monospace"
                    width: parent.width
                    elide: Text.ElideMiddle
                    horizontalAlignment: Text.AlignLeft
                }
            }

            SettingsRow {
                body: StyledText {
                    text: I18n.tr("Place plugin directories here. Each plugin should have a plugin.json manifest file.")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    width: parent.width
                    horizontalAlignment: Text.AlignLeft
                }
            }

            Flow {
                width: parent.width
                spacing: Theme.spacingS

                CyButton {
                    text: PluginService.pluginDirectoryExists ? I18n.tr("Open folder") : I18n.tr("Create folder")
                    iconName: PluginService.pluginDirectoryExists ? "folder_open" : "create_new_folder"
                    maximumWidth: parent.width
                    wrapText: true
                    onClicked: {
                        if (PluginService.pluginDirectoryExists) {
                            PluginService.openPluginDirectory();
                            return;
                        }
                        PluginService.createPluginDirectory();
                    }
                }
                CyButton {
                    text: I18n.tr("Scan", "verb, button that scans for plugins, wifi networks or bluetooth devices")
                    iconName: "refresh"
                    backgroundColor: Theme.secondaryContainer
                    textColor: Theme.onSecondaryContainer
                    maximumWidth: parent.width
                    wrapText: true
                    enabled: !CyShellService.checkingPluginUpdates
                    onClicked: {
                        PluginService.scanPlugins();
                        if (CyShellService.backendAvailable && CyShellService.apiVersion >= 8)
                            CyShellService.listInstalled(undefined, true);
                    }
                }
            }
        }

        SettingsCard {
            iconName: "cloud_download"
            title: I18n.tr("Registries", "plugin settings card title, plugin registry sources")
            settingKey: "pluginRegistries"
            tags: ["plugins", "registry", "registries", "sources", "git", "themes"]
            visible: CyShellService.backendAvailable && CyShellService.apiVersion >= 29

            SettingsRow {
                body: StyledText {
                    text: I18n.tr("Sources for plugins and themes. Registries are git repositories with a plugins/ or themes/ directory.")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    width: parent.width
                    horizontalAlignment: Text.AlignLeft
                }
            }

            SettingsRow {
                visible: root.registryError !== ""
                title: I18n.tr("Error")
                subtitle: root.registryError
                subtitleColor: Theme.error
                CyButton {
                    text: I18n.tr("Retry", "retry failed action button")
                    enabled: !root.registryBusy
                    onClicked: root.refreshRegistries()
                }
            }

            Repeater {
                model: CyShellService.registries

                SettingsRow {
                    id: registryRow
                    required property var modelData

                    title: modelData.name
                    subtitle: modelData.url
                    trailingBadge: modelData.official ? I18n.tr("official") : ""

                    CyActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "delete"
                        iconColor: Theme.error
                        Accessible.name: I18n.tr("Remove")
                        visible: !registryRow.modelData.official
                        enabled: !root.registryBusy
                        onClicked: {
                            root.registryBusy = true;
                            root.registryError = "";
                            CyShellService.removeRegistry(registryRow.modelData.name, response => {
                                root.registryBusy = false;
                                root.registryError = response.error || "";
                            });
                        }
                    }
                }
            }

            SettingsTextFieldRow {
                id: registryNameField
                leftIconName: "badge"
                text: I18n.tr("Name")
            }

            SettingsTextFieldRow {
                id: registryUrlField
                leftIconName: "link"
                text: I18n.tr("URL", "Plugin registry repository address")
                placeholderText: "https://github.com/user/registry.git"

                actions: CyButton {
                    text: I18n.tr("Add")
                    enabled: !root.registryBusy && registryNameField.value.trim() !== "" && registryUrlField.value.trim() !== ""
                    onClicked: {
                        root.registryBusy = true;
                        root.registryError = "";
                        CyShellService.addRegistry(registryNameField.value.trim(), registryUrlField.value.trim(), response => {
                            root.registryBusy = false;
                            if (response.error) {
                                root.registryError = response.error;
                                return;
                            }
                            registryNameField.value = "";
                            registryUrlField.value = "";
                        });
                    }
                }
            }
        }
    }
}
