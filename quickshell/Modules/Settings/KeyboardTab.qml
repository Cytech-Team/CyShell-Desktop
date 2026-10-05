import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property var knownLayouts: [
        {code: "us", label: I18n.tr("English (US)")},
        {code: "gb", label: I18n.tr("English (UK)")},
        {code: "th", label: I18n.tr("Thai")},
        {code: "de", label: I18n.tr("German")},
        {code: "fr", label: I18n.tr("French")},
        {code: "es", label: I18n.tr("Spanish")},
        {code: "jp", label: I18n.tr("Japanese")},
        {code: "kr", label: I18n.tr("Korean")},
        {code: "cn", label: I18n.tr("Chinese")},
        {code: "ru", label: I18n.tr("Russian")}
    ]

    readonly property var layoutCodes: {
        const configured = SettingsData.keyboardLayouts.trim();
        if (configured)
            return configured.split(",").map(code => code.trim()).filter(code => code.length > 0);
        return KeyboardLayoutService.layoutNames.map(name => root.layoutCode(name)).filter(code => code.length > 0);
    }

    readonly property var availableLayoutChoices: knownLayouts.filter(layout => !layoutCodes.includes(layout.code))

    function layoutCode(name) {
        const value = String(name ?? "").trim().toLowerCase();
        const layout = knownLayouts.find(item => item.code === value || item.label.toLowerCase() === value);
        return layout?.code ?? "";
    }

    function layoutLabel(code) {
        return knownLayouts.find(item => item.code === code)?.label ?? code;
    }

    function addLayout(code) {
        if (!code || layoutCodes.includes(code))
            return;
        SettingsData.set("keyboardLayouts", [...layoutCodes, code].join(","));
    }

    function removeLayout(code) {
        SettingsData.set("keyboardLayouts", layoutCodes.filter(item => item !== code).join(","));
    }

    ConfigInclude {
        id: inputInclude
        includeKind: "input"
        procTag: "input-include-keyboard"
        onFixed: SettingsData.updateCompositorInput()
    }

    SettingsPage {
        id: settingsColumn

        IncludeSetupBanner {
            include: inputInclude
            visibleCondition: CompositorService.supportsInputConfig
        }

        SettingsCard {
            width: parent.width
            tags: ["keyboard", "layout", "language", "input", "xkb"]
            title: I18n.tr("Layouts")
            settingKey: "keyboardLayoutsSettings"
            iconName: "keyboard"

            Repeater {
                model: root.layoutCodes

                delegate: SettingsRow {
                    required property string modelData
                    title: root.layoutLabel(modelData)
                    subtitle: modelData
                    iconName: "keyboard"

                    CyActionButton {
                        iconName: "close"
                        iconSize: Theme.iconSizeMedium
                        tooltipText: I18n.tr("Remove language")
                        onClicked: root.removeLayout(modelData)
                    }
                }
            }

            SettingsDropdownRow {
                text: I18n.tr("Add language")
                description: I18n.tr("Add a keyboard layout for another language.")
                currentValue: I18n.tr("Choose a language")
                options: root.availableLayoutChoices.map(layout => layout.label)
                enabled: root.availableLayoutChoices.length > 0
                onValueChanged: value => {
                    const layout = root.availableLayoutChoices.find(item => item.label === value);
                    if (layout)
                        root.addLayout(layout.code);
                }
            }

            SettingsDropdownRow {
                tags: ["keyboard", "layout", "switch", "shortcut", "xkb"]
                settingKey: "keyboardOptions"
                resetKeys: []
                text: I18n.tr("Switch layout shortcut")
                options: [I18n.tr("Alt + Shift"), I18n.tr("Ctrl + Shift"), I18n.tr("Caps lock"), I18n.tr("Super + Space"), I18n.tr("Custom / None")]
                currentValue: {
                    const opt = SettingsData.keyboardOptions;
                    if (opt.includes("grp:alt_shift_toggle"))
                        return options[0];
                    if (opt.includes("grp:ctrl_shift_toggle"))
                        return options[1];
                    if (opt.includes("grp:caps_toggle"))
                        return options[2];
                    if (opt.includes("grp:win_space_toggle"))
                        return options[3];
                    return options[4];
                }
                onValueChanged: value => {
                    const idx = options.indexOf(value);
                    let opt = SettingsData.keyboardOptions.split(",").filter(o => !o.startsWith("grp:")).join(",");

                    let newGrp = "";
                    switch (idx) {
                    case 0:
                        newGrp = "grp:alt_shift_toggle";
                        break;
                    case 1:
                        newGrp = "grp:ctrl_shift_toggle";
                        break;
                    case 2:
                        newGrp = "grp:caps_toggle";
                        break;
                    case 3:
                        newGrp = "grp:win_space_toggle";
                        break;
                    }

                    if (newGrp)
                        opt = opt ? opt + "," + newGrp : newGrp;
                    SettingsData.set("keyboardOptions", opt);
                }
            }

            SettingsTextFieldRow {
                resetKeys: ["keyboardOptions"]
                leftIconName: "tune"
                text: I18n.tr("XKB options")
                description: I18n.tr("Advanced comma-separated libxkbcommon options.")
                value: SettingsData.keyboardOptions
                placeholderText: "compose:ralt,ctrl:nocaps"
                onValueEdited: value => SettingsData.set("keyboardOptions", value)
            }

            SettingsTextFieldRow {
                resetKeys: ["keyboardVariants"]
                leftIconName: "keyboard"
                text: I18n.tr("Variant", "noun, xkb keyboard layout variant field label")
                value: SettingsData.keyboardVariants
                placeholderText: "colemak"
                onValueEdited: value => SettingsData.set("keyboardVariants", value)
            }

            SettingsTextFieldRow {
                resetKeys: ["keyboardModel"]
                leftIconName: "keyboard"
                text: I18n.tr("Model", "noun, hardware model of keyboard, display or printer")
                value: SettingsData.keyboardModel
                placeholderText: "pc104"
                onValueEdited: value => SettingsData.set("keyboardModel", value)
            }

            SettingsTextFieldRow {
                resetKeys: ["keyboardKeymapFile"]
                leftIconName: "description"
                text: I18n.tr("Keymap file")
                description: I18n.tr("Direct path to a .xkb keymap file. Overrides layouts/variants above.")
                value: SettingsData.keyboardKeymapFile
                placeholderText: "~/.config/keymap.xkb"
                onValueEdited: value => SettingsData.set("keyboardKeymapFile", value)
            }
        }

        SettingsCard {
            width: parent.width
            tags: ["keyboard", "repeat", "delay", "rate", "numlock", "behavior"]
            title: I18n.tr("Behavior")
            settingKey: "keyboardBehaviorSettings"
            iconName: "settings"

            SettingsButtonGroupRow {
                tags: ["keyboard", "track", "layout"]
                settingKey: "keyboardTrackLayout"
                text: I18n.tr("Remember layout")
                model: [I18n.tr("Globally", "adverb, remember keyboard layout option, opposite of per window"), I18n.tr("Per window")]
                currentIndex: SettingsData.keyboardTrackLayout === "window" ? 1 : 0
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    SettingsData.set("keyboardTrackLayout", index === 1 ? "window" : "global");
                }
            }

            SettingsToggleRow {
                tags: ["keyboard", "numlock", "startup"]
                settingKey: "keyboardNumlock"
                text: I18n.tr("Num Lock")
                description: I18n.tr("Turn Num Lock on when the session starts.")
                checked: SettingsData.keyboardNumlock
                onToggled: checked => SettingsData.set("keyboardNumlock", checked)
            }

            SettingsSliderRow {
                tags: ["keyboard", "repeat", "delay", "speed"]
                settingKey: "keyboardRepeatDelay"
                text: I18n.tr("Repeat delay")
                value: SettingsData.keyboardRepeatDelay || 600
                minimum: 100
                maximum: 2000
                step: 50
                unit: "ms"
                onSliderValueChanged: newValue => SettingsData.set("keyboardRepeatDelay", newValue)
            }

            SettingsSliderRow {
                tags: ["keyboard", "repeat", "rate", "speed"]
                settingKey: "keyboardRepeatRate"
                text: I18n.tr("Repeat rate")
                value: SettingsData.keyboardRepeatRate || 25
                minimum: 1
                maximum: 100
                step: 1
                unit: "/s"
                onSliderValueChanged: newValue => SettingsData.set("keyboardRepeatRate", newValue)
            }
        }
    }
}
