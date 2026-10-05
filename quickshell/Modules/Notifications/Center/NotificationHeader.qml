import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Notifications

Item {
    id: root

    property var keyboardController: null
    property int currentTab: 0
    property var transientSurfaceTracker: null
    property bool modal: false
    property bool calendarLayout: false
    readonly property string currentLabel: {
        const count = NotificationService.notifications.length;
        if (count === 0)
            return I18n.tr("Current", "notification center tab");
        return I18n.tr("Current (%1)", "notification center tab, %1 is the notification count").arg(count);
    }
    readonly property string historyLabel: {
        const count = NotificationService.historyList.length;
        if (count === 0)
            return I18n.tr("History", "notification center tab");
        return I18n.tr("History (%1)", "notification center tab, %1 is the history entry count").arg(count);
    }
    signal settingsRequested
    signal closeRequested

    width: parent.width
    implicitHeight: root.calendarLayout ? Theme.buttonHeightS : Theme.buttonHeightXS
    height: implicitHeight
    onVisibleChanged: {
        tabs.interactionStarted = false;
        tabs.userInteracted = false;
    }

    readonly property bool settingsNotificationHistoryEnabled: SettingsData.notificationHistoryEnabled

    onSettingsNotificationHistoryEnabledChanged: {
        if (!settingsNotificationHistoryEnabled)
            currentTab = 0;
    }

    StyledTextMetrics {
        id: currentLabelMetrics
        text: root.currentLabel
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
    }

    StyledTextMetrics {
        id: historyLabelMetrics
        text: root.historyLabel
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
    }

    Row {
        id: leadingActions
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS
        visible: !root.calendarLayout

        CyActionButton {
            id: dndButton
            visible: !root.calendarLayout
            iconName: SessionData.doNotDisturb ? "notifications_off" : "notifications"
            buttonSize: Theme.buttonHeightXS
            backgroundColor: SessionData.doNotDisturb ? Theme.primaryContainer : "transparent"
            iconColor: SessionData.doNotDisturb ? Theme.onPrimaryContainer : Theme.onSurfaceVariant
            tooltipText: I18n.tr("Do not disturb") + ": " + (SessionData.doNotDisturb ? DndPresets.status : I18n.tr("Off"))
            onClicked: {
                durationMenu.currentValue = SessionData.doNotDisturb ? DndPresets.status : I18n.tr("Off");
                durationMenu.openDropdownMenu();
            }
        }

        CyActionButton {
            visible: root.keyboardController !== null && !root.calendarLayout
            iconName: "info"
            buttonSize: Theme.buttonHeightXS
            tooltipText: I18n.tr("Keyboard shortcuts")
            onClicked: root.keyboardController.showKeyboardHints = !root.keyboardController.showKeyboardHints
        }
    }

    CyButtonGroup {
        id: tabs
        anchors.left: leadingActions.right
        anchors.right: actions.left
        anchors.leftMargin: Theme.spacingS
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        fillWidth: true
        currentIndex: root.currentTab
        size: "small"
        checkEnabled: false
        iconOnly: width < (Math.max(currentLabelMetrics.width, historyLabelMetrics.width) + buttonPadding * 2) * 2 + spacing
        visible: SettingsData.notificationHistoryEnabled && !root.calendarLayout
        model: [
            {
                text: root.currentLabel,
                icon: iconOnly ? "inbox" : ""
            },
            {
                text: root.historyLabel,
                icon: iconOnly ? "history" : ""
            }
        ]
        onSelectionChanged: (index, selected) => {
            if (selected)
                root.currentTab = index;
        }
    }

    Row {
        id: actions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS
        visible: !root.calendarLayout

        CyActionButton {
            iconName: "settings"
            buttonSize: Theme.buttonHeightXS
            tooltipText: I18n.tr("Settings")
            onClicked: root.settingsRequested()
        }
        CyActionButton {
            iconName: "delete_sweep"
            buttonSize: Theme.buttonHeightXS
            tooltipText: I18n.tr("Clear All")
            enabled: root.currentTab === 0 ? NotificationService.notifications.length > 0 : NotificationService.historyList.length > 0
            backgroundColor: Theme.secondaryContainer
            iconColor: Theme.onSecondaryContainer
            onClicked: {
                if (root.currentTab === 0) {
                    NotificationService.clearAllNotifications();
                    return;
                }
                NotificationService.clearHistory();
            }
        }
        CyActionButton {
            visible: root.modal
            iconName: "close"
            buttonSize: Theme.buttonHeightXS
            tooltipText: I18n.tr("Close")
            onClicked: root.closeRequested()
        }
    }

    CyDropdown {
        id: durationMenu
        showTrigger: false
        popupAnchorItem: root.calendarLayout ? calendarDndButton : dndButton
        popupWidth: NotificationMetrics.menuWidth
        alignPopupRight: I18n.isRtl
        options: [I18n.tr("Off")].concat(DndPresets.presetOptions.map(option => option.label))
        currentValue: SessionData.doNotDisturb ? DndPresets.status : I18n.tr("Off")
        transientSurfaceTracker: root.transientSurfaceTracker
        onMenuOpenChanged: {
            if (!menuOpen && root.visible)
                (root.calendarLayout ? calendarDndButton : dndButton).forceActiveFocus();
        }
        onValueChanged: value => {
            if (value === I18n.tr("Off")) {
                SessionData.setDoNotDisturb(false);
                return;
            }
            const option = DndPresets.presetOptions.find(option => option.label === value);
            if (option)
                DndPresets.selectPreset(option);
        }
    }

    StyledText {
        visible: root.calendarLayout
        anchors.left: parent.left
        anchors.right: calendarActions.left
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        text: root.currentTab === 0 ? I18n.tr("Notifications") : I18n.tr("History")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
        elide: Text.ElideRight
    }

    Row {
        id: calendarActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS
        visible: root.calendarLayout

        CyActionButton {
            id: calendarDndButton
            iconName: SessionData.doNotDisturb ? "notifications_off" : "notifications"
            buttonSize: Theme.buttonHeightXS
            backgroundColor: SessionData.doNotDisturb ? Theme.primaryContainer : "transparent"
            iconColor: SessionData.doNotDisturb ? Theme.onPrimaryContainer : Theme.onSurfaceVariant
            tooltipText: I18n.tr("Do not disturb") + ": " + (SessionData.doNotDisturb ? DndPresets.status : I18n.tr("Off"))
            onClicked: {
                durationMenu.currentValue = SessionData.doNotDisturb ? DndPresets.status : I18n.tr("Off");
                durationMenu.openDropdownMenu();
            }
        }

        CyActionButton {
            visible: SettingsData.notificationHistoryEnabled
            iconName: root.currentTab === 0 ? "history" : "inbox"
            buttonSize: Theme.buttonHeightXS
            tooltipText: root.currentTab === 0 ? root.historyLabel : root.currentLabel
            Accessible.name: tooltipText
            onClicked: root.currentTab = root.currentTab === 0 ? 1 : 0
        }

        CyActionButton {
            iconName: "settings"
            buttonSize: Theme.buttonHeightXS
            tooltipText: I18n.tr("Settings")
            onClicked: root.settingsRequested()
        }

        CyActionButton {
            iconName: "delete_sweep"
            buttonSize: Theme.buttonHeightXS
            tooltipText: I18n.tr("Clear All")
            enabled: root.currentTab === 0 ? NotificationService.notifications.length > 0 : NotificationService.historyList.length > 0
            backgroundColor: Theme.secondaryContainer
            iconColor: Theme.onSecondaryContainer
            onClicked: {
                if (root.currentTab === 0) {
                    NotificationService.clearAllNotifications();
                    return;
                }
                NotificationService.clearHistory();
            }
        }
    }
}
