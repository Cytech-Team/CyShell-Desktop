import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

FocusScope {
    id: root

    property var editingApp: null
    property string editAppId: ""
    property string editLocaleCode: ""

    readonly property string _systemDefaultLocaleLabel: I18n.tr("System default")

    signal closeRequested

    function _localeDisplayName(localeCode) {
        if (!localeCode)
            return _systemDefaultLocaleLabel;
        const locale = I18n.presentLocales[localeCode];
        if (!locale)
            return localeCode;
        const nativeName = locale.nativeLanguageName;
        if (nativeName.length === 0)
            return localeCode;
        const displayName = nativeName[0].toUpperCase() + nativeName.slice(1);
        const hasDuplicate = Object.keys(I18n.presentLocales).some(code => code !== localeCode && I18n.presentLocales[code]?.nativeLanguageName === nativeName);
        return hasDuplicate ? `${displayName} (${localeCode})` : displayName;
    }

    function _localeOptions() {
        const options = [_systemDefaultLocaleLabel];
        const localeCodes = Object.keys(I18n.presentLocales).sort();
        for (const localeCode of localeCodes)
            options.push(_localeDisplayName(localeCode));
        return options;
    }

    function _localeCodeForDisplayName(displayName) {
        if (displayName === _systemDefaultLocaleLabel)
            return "";
        for (const localeCode of Object.keys(I18n.presentLocales)) {
            if (_localeDisplayName(localeCode) === displayName)
                return localeCode;
        }
        return "";
    }

    function loadOverride() {
        var existing = SessionData.getAppOverride(editAppId);
        editNameField.text = existing?.name || "";
        editIconField.text = existing?.icon || "";
        editCommentField.text = existing?.comment || "";
        editLocaleCode = existing?.locale || "";
        editLocaleDropdown.currentValue = _localeDisplayName(editLocaleCode);
        editEnvVarsField.text = existing?.envVars || "";
        editExtraFlagsField.text = existing?.extraFlags || "";
        Qt.callLater(() => editNameField.forceActiveFocus());
    }

    function saveAppOverride() {
        var override = Object.assign({}, SessionData.getAppOverride(editAppId) || {});
        delete override.name;
        delete override.icon;
        delete override.comment;
        delete override.locale;
        delete override.envVars;
        delete override.extraFlags;
        if (editNameField.text.trim())
            override.name = editNameField.text.trim();
        if (editIconField.text.trim())
            override.icon = editIconField.text.trim();
        if (editCommentField.text.trim())
            override.comment = editCommentField.text.trim();
        if (editLocaleCode)
            override.locale = editLocaleCode;
        if (editEnvVarsField.text.trim())
            override.envVars = editEnvVarsField.text.trim();
        if (editExtraFlagsField.text.trim())
            override.extraFlags = editExtraFlagsField.text.trim();
        SessionData.setAppOverride(editAppId, override);
        closeRequested();
    }

    function resetAppOverride() {
        SessionData.clearAppOverride(editAppId);
        closeRequested();
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            closeRequested();
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (event.modifiers & Qt.ControlModifier) {
                saveAppOverride();
                event.accepted = true;
            }
        } else if (event.key === Qt.Key_S && event.modifiers & Qt.ControlModifier) {
            saveAppOverride();
            event.accepted = true;
        }
    }

    Column {
        anchors.fill: parent
        spacing: Theme.spacingM

        Row {
            width: parent.width
            spacing: Theme.spacingM

            Rectangle {
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("Back")
                width: Theme.buttonHeightS
                height: Theme.buttonHeightS
                radius: Theme.cornerRadius
                color: backButtonArea.containsMouse ? Theme.surfaceHover : Theme.withAlpha(Theme.surfaceHover, 0)

                CyIcon {
                    anchors.centerIn: parent
                    name: "arrow_back"
                    size: Theme.iconSizeMedium
                    color: Theme.onSurface
                }

                MouseArea {
                    id: backButtonArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeRequested()
                }
            }

            Image {
                width: Theme.buttonHeightS
                height: Theme.buttonHeightS
                source: Paths.resolveIconUrl(root.editingApp?.icon || "application-x-executable")
                sourceSize.width: Theme.buttonHeightS
                sourceSize.height: Theme.buttonHeightS
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXXS

                StyledText {
                    text: I18n.tr("Edit App")
                    font.pixelSize: Theme.fontSizeLarge
                    color: Theme.onSurface
                    font.weight: Theme.fontWeightMedium
                }

                StyledText {
                    text: root.editingApp?.name || ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.onSurfaceVariant
                }
            }
        }

        Rectangle {
            width: parent.width
            height: Theme.outlineWidth
            color: Theme.outlineMedium
        }

        CyFlickable {
            width: parent.width
            height: parent.height - y - buttonsRow.height - Theme.spacingM
            contentHeight: editFieldsColumn.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: editFieldsColumn
                width: parent.width
                spacing: Theme.spacingS

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Name")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurface
                        font.weight: Theme.fontWeightMedium
                    }

                    CyTextField {
                        id: editNameField
                        width: parent.width
                        placeholderText: root.editingApp?.name || ""
                        keyNavigationTab: editIconField
                        keyNavigationBacktab: editExtraFlagsField
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Icon")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurface
                        font.weight: Theme.fontWeightMedium
                    }

                    CyTextField {
                        id: editIconField
                        width: parent.width
                        placeholderText: root.editingApp?.icon || ""
                        keyNavigationTab: editCommentField
                        keyNavigationBacktab: editNameField
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Description", "noun, text field label")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurface
                        font.weight: Theme.fontWeightMedium
                    }

                    CyTextField {
                        id: editCommentField
                        width: parent.width
                        placeholderText: root.editingApp?.comment || ""
                        keyNavigationTab: editLocaleDropdown
                        keyNavigationBacktab: editIconField
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Application language")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurface
                        font.weight: Theme.fontWeightMedium
                    }

                    StyledText {
                        text: I18n.tr("Choose the language used by this app. System default follows your desktop language.")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurfaceVariant
                        wrapMode: Text.WordWrap
                    }

                    CyDropdown {
                        id: editLocaleDropdown
                        width: parent.width
                        options: root._localeOptions()
                        currentValue: root._systemDefaultLocaleLabel
                        emptyText: root._systemDefaultLocaleLabel
                        maxPopupHeight: Theme.menuMaxHeight

                        KeyNavigation.tab: editEnvVarsField
                        KeyNavigation.backtab: editCommentField

                        onValueChanged: value => root.editLocaleCode = root._localeCodeForDisplayName(value)
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Environment Variables")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurface
                        font.weight: Theme.fontWeightMedium
                    }

                    StyledText {
                        text: "KEY=value KEY2=value2"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurfaceVariant
                    }

                    CyTextField {
                        id: editEnvVarsField
                        width: parent.width
                        placeholderText: "VAR=value"
                        keyNavigationTab: editExtraFlagsField
                        keyNavigationBacktab: editLocaleDropdown
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Extra Arguments")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurface
                        font.weight: Theme.fontWeightMedium
                    }

                    CyTextField {
                        id: editExtraFlagsField
                        width: parent.width
                        placeholderText: "--flag --option=value"
                        keyNavigationTab: editNameField
                        keyNavigationBacktab: editEnvVarsField
                    }
                }
            }
        }

        Row {
            id: buttonsRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spacingM

            CyButton {
                text: I18n.tr("Reset", "verb, button that restores defaults")
                backgroundColor: Theme.chipSurface
                textColor: Theme.error
                visible: SessionData.getAppOverride(root.editAppId) !== null
                onClicked: root.resetAppOverride()
            }

            CyButton {
                text: I18n.tr("Cancel")
                backgroundColor: Theme.chipSurface
                textColor: Theme.onSurface
                onClicked: root.closeRequested()
            }

            CyButton {
                text: I18n.tr("Save")
                onClicked: root.saveAppOverride()
            }
        }
    }
}
