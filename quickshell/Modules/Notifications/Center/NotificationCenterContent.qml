pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Notifications
import qs.Services

Item {
    id: root

    required property var host
    property var externalKeyboardController: null

    readonly property alias notificationList: notificationList
    readonly property alias notificationHeader: notificationHeader
    readonly property int currentTab: notificationHeader.currentTab
    readonly property bool hostOwnsHeight: root.host.hostOwnsHeight ?? false
    readonly property real desiredPanelHeight: Math.min(maxContentHeight, NotificationMetrics.centerMaxHeight + Theme.buttonHeightM * 2)
    readonly property real panelSpacing: Theme.spacingS
    readonly property real panelPadding: Theme.spacingM
    readonly property real panelContentHeight: Math.max(0, desiredPanelHeight - Theme.spacingXS * 2 - panelSpacing)
    readonly property real notificationPaneHeight: panelContentHeight * 0.32
    readonly property real expandedCalendarHeight: panelContentHeight - notificationPaneHeight

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property real maxContentHeight: {
        const requested = root.host.maxContentHeight ?? 0;
        if (requested > 0)
            return requested;
        return (root.host.screen?.height ?? 1080) * NotificationMetrics.screenHeightRatio;
    }

    readonly property real targetImplicitHeight: root.hostOwnsHeight ? height : desiredPanelHeight - (calendarPanel.calendarExpanded ? 0 : expandedCalendarHeight - calendarPanel.collapsedHeight)

    implicitHeight: root.hostOwnsHeight ? height : targetImplicitHeight

    function handleKey(event) {
        if (event.key === Qt.Key_Escape) {
            root.host.close();
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Left) {
            if (notificationHeader.currentTab > 0) {
                notificationHeader.currentTab = 0;
                event.accepted = true;
            }
            return;
        }

        if (event.key === Qt.Key_Right) {
            if (notificationHeader.currentTab === 0 && SettingsData.notificationHistoryEnabled) {
                notificationHeader.currentTab = 1;
                event.accepted = true;
            }
            return;
        }

        if (notificationHeader.currentTab === 1) {
            historyList.handleKey(event);
            return;
        }

        if (root.externalKeyboardController)
            root.externalKeyboardController.handleKey(event);
    }

    FocusScope {
        id: contentColumn

        anchors.fill: parent
        anchors.margins: 0
        focus: true

        Column {
            id: contentColumnInner

            anchors.fill: parent
            anchors.margins: Theme.spacingXS
            spacing: root.panelSpacing

            Rectangle {
                id: notificationPane

                width: parent.width
                height: root.notificationPaneHeight
                radius: Theme.cornerRadiusL
                color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
                border.width: Theme.layerOutlineWidth
                border.color: Theme.outlineVariant
                clip: true

                Item {
                    anchors.fill: parent
                    anchors.margins: root.panelPadding

                    NotificationHeader {
                        id: notificationHeader

                        objectName: "notificationHeader"
                        width: parent.width
                        calendarLayout: true
                        transientSurfaceTracker: root.host.transientSurfaceTracker ?? null
                        onSettingsRequested: {
                            if (typeof root.host.requestSettings === "function")
                                root.host.requestSettings();
                        }
                    }

                    Item {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: notificationHeader.bottom
                        anchors.bottom: parent.bottom
                        anchors.topMargin: Theme.spacingS

                        KeyboardNavigatedNotificationList {
                            id: notificationList

                            objectName: "notificationList"
                            anchors.fill: parent
                            visible: notificationHeader.currentTab === 0
                            cardAnimateExpansion: root.host.animateCardExpansion ?? true
                            trackStableContentHeight: !root.hostOwnsHeight
                            trackSessionContentHeight: root.hostOwnsHeight
                            transientSurfaceTracker: root.host.transientSurfaceTracker ?? null
                        }

                        HistoryNotificationList {
                            id: historyList

                            visible: notificationHeader.currentTab === 1
                            anchors.fill: parent
                        }
                    }
                }

                NotificationKeyboardHints {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: root.panelPadding
                    showHints: notificationHeader.currentTab === 0 ? (root.externalKeyboardController?.showKeyboardHints ?? false) : historyList.showKeyboardHints
                    z: 200
                }
            }

            NotificationCalendar {
                id: calendarPanel
                width: parent.width
                expandedHeight: root.expandedCalendarHeight
                onFocusSessionStarted: {
                    if (typeof root.host.close === "function")
                        root.host.close();
                }
            }
        }
    }

}
