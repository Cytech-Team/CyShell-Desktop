import QtQuick
import qs.Common
import qs.Modals.FileBrowser
import qs.Services
import qs.Widgets
import qs.Modules.Settings
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var page: null
    readonly property var dock: page?.appStore ?? null
    readonly property string compositorLabel: CompositorService.displayName || I18n.tr("Compositor")
    readonly property bool launcherLogoColorCustom: {
        const override = root.dock?.get("launcherLogoColorOverride") ?? "";
        return (root.dock?.get("launcherEnabled") ?? false) && (root.dock?.get("launcherLogoMode") ?? "apps") !== "apps" && override !== "" && override !== "primary" && override !== "surface";
    }

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    FileBrowserModal {
        id: logoFileBrowser
        browserTitle: I18n.tr("Select Dock Launcher Logo")
        browserType: "generic"
        filterExtensions: ["*.svg", "*.png", "*.jpg", "*.jpeg", "*.webp"]
        onFileSelected: path => root.dock?.set("launcherLogoCustomPath", path.replace("file://", ""))
    }

    SettingsCard {
        iconName: "apps"
        title: I18n.tr("Launcher button")
        settingKey: "dockLauncher"

        SettingsToggleRow {
            resetStore: root.dock
            resetKeys: ["launcherEnabled"]
            text: I18n.tr("Show")
            checked: root.dock?.get("launcherEnabled") ?? true
            onToggled: checked => root.dock?.set("launcherEnabled", checked)
        }

        SettingsButtonGroupRow {
            resetStore: root.dock
            resetKeys: ["launcherLogoMode"]
            readonly property var modes: ["apps", "os", "dank", "compositor", "custom"]

            text: I18n.tr("Icon")
            enabled: root.dock?.get("launcherEnabled") ?? true
            buttonPadding: Theme.spacingS
            minButtonWidth: 44
            textSize: Theme.fontSizeSmall
            model: [I18n.tr("Apps Icon"), I18n.tr("OS Logo"), "Dank", root.compositorLabel, I18n.tr("Custom")]
            currentIndex: Math.max(0, modes.indexOf(root.dock?.get("launcherLogoMode") ?? "apps"))
            onSelectionChanged: (index, selected) => {
                if (selected)
                    root.dock?.set("launcherLogoMode", modes[index]);
            }
        }

        SettingsTextFieldRow {
            resetStore: root.dock
            resetKeys: ["launcherLogoCustomPath"]
            text: I18n.tr("Custom")
            visible: (root.dock?.get("launcherEnabled") ?? true) && (root.dock?.get("launcherLogoMode") ?? "apps") === "custom"
            placeholderText: I18n.tr("Select an image file...")
            value: root.dock?.get("launcherLogoCustomPath") ?? ""
            onEditingFinished: value => root.dock?.set("launcherLogoCustomPath", value.trim())

            actions: CyActionButton {
                iconName: "folder_open"
                Accessible.name: I18n.tr("Select Dock Launcher Logo")
                onClicked: logoFileBrowser.open()
            }
        }

        ColorDropdownRow {
            resetStore: root.dock
            resetKeys: ["launcherLogoColorOverride"]
            text: I18n.tr("Color override")
            visible: (root.dock?.get("launcherEnabled") ?? true) && (root.dock?.get("launcherLogoMode") ?? "apps") !== "apps"
            options: [({"value": "", "label": I18n.tr("Default")}), ({"value": "primary", "label": I18n.tr("Primary")}), ({"value": "surface", "label": I18n.tr("Surface", "color option")}), ({"value": "custom", "label": I18n.tr("Custom")})]
            currentMode: {
                const override = root.dock?.get("launcherLogoColorOverride") ?? "";
                if (override === "" || override === "primary" || override === "surface")
                    return override;
                return "custom";
            }
            customColor: root.launcherLogoColorCustom ? (root.dock?.get("launcherLogoColorOverride") ?? "#ffffff") : "#ffffff"
            pickerTitle: I18n.tr("Choose Launcher Logo Color")
            onModeSelected: mode => {
                if (mode !== "custom") {
                    root.dock?.set("launcherLogoColorOverride", mode);
                    return;
                }
                if (!root.launcherLogoColorCustom)
                    root.dock?.set("launcherLogoColorOverride", "#ffffff");
            }
            onCustomColorSelected: selectedColor => root.dock?.set("launcherLogoColorOverride", selectedColor)
        }

        SettingsSliderRow {
            resetStore: root.dock
            resetKeys: ["launcherLogoSizeOffset"]
            text: I18n.tr("Size offset")
            visible: (root.dock?.get("launcherEnabled") ?? true) && (root.dock?.get("launcherLogoMode") ?? "apps") !== "apps"
            value: root.dock?.get("launcherLogoSizeOffset") ?? 0
            minimum: -12
            maximum: 12
            onSliderValueChanged: value => root.dock?.set("launcherLogoSizeOffset", value)
        }

        SettingsSliderRow {
            resetStore: root.dock
            resetKeys: ["launcherLogoBrightness"]
            text: I18n.tr("Brightness")
            visible: root.launcherLogoColorCustom
            value: Math.round((root.dock?.get("launcherLogoBrightness") ?? 0.5) * 100)
            minimum: 0
            maximum: 100
            onSliderValueChanged: value => root.dock?.set("launcherLogoBrightness", value / 100)
        }

        SettingsSliderRow {
            resetStore: root.dock
            resetKeys: ["launcherLogoContrast"]
            text: I18n.tr("Contrast")
            visible: root.launcherLogoColorCustom
            value: Math.round((root.dock?.get("launcherLogoContrast") ?? 1) * 100)
            minimum: 0
            maximum: 200
            onSliderValueChanged: value => root.dock?.set("launcherLogoContrast", value / 100)
        }
    }

    SettingsCard {
        iconName: "delete"
        title: I18n.tr("Trash")
        settingKey: "dockTrash"

        SettingsToggleRow {
            resetStore: root.dock
            resetKeys: ["showTrash"]
            text: I18n.tr("Show")
            checked: root.dock?.get("showTrash") ?? false
            onToggled: checked => root.dock?.set("showTrash", checked)
        }

        SettingsDropdownRow {
            resetStore: root.dock
            resetKeys: ["trashFileManager"]
            text: I18n.tr("Open with", "trash setting label, which file manager opens the trash")
            enabled: root.dock?.get("showTrash") ?? false
            currentValue: root.dock?.get("trashFileManager") ?? "default"
            options: TrashService.availableFileManagers || []
            onValueChanged: value => root.dock?.set("trashFileManager", value)
        }

        SettingsTextFieldRow {
            resetStore: root.dock
            resetKeys: ["trashCustomCommand"]
            text: I18n.tr("Custom command")
            visible: (root.dock?.get("showTrash") ?? false) && (root.dock?.get("trashFileManager") ?? "default") === "custom"
            placeholderText: "nemo trash:///"
            value: root.dock?.get("trashCustomCommand") ?? ""
            onEditingFinished: value => root.dock?.set("trashCustomCommand", value.trim())
        }
    }
}
