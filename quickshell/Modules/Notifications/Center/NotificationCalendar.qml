pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

Rectangle {
    id: root

    signal focusSessionStarted(int durationMinutes)

    property real expandedHeight: Theme.buttonHeightM * 8
    property bool calendarExpanded: true
    property int focusMinutes: 30
    property date selectedDate: systemClock.date
    property date displayDate: systemClock.date
    property bool userSelectedDate: false
    property bool userBrowsingCalendar: false

    readonly property real panelPadding: Theme.spacingM
    readonly property real dateRowHeight: Theme.buttonHeightS
    readonly property real focusRowHeight: Theme.buttonHeightS
    readonly property real collapsedHeight: panelPadding * 2 + dateRowHeight + focusRowHeight + Theme.spacingM
    readonly property date currentDate: systemClock.date
    readonly property bool focusSessionActive: SessionData.doNotDisturb && SessionData.doNotDisturbUntil > currentDate.getTime()
    readonly property int remainingFocusMinutes: Math.max(0, Math.ceil((SessionData.doNotDisturbUntil - currentDate.getTime()) / 60000))
    readonly property int firstDayOfWeek: {
        const configured = SettingsData.firstDayOfWeek;
        const qtDay = configured < 0 || configured >= 7 ? Qt.locale().firstDayOfWeek : configured;
        return qtDay % 7;
    }
    readonly property var weekdayNames: {
        const names = [];
        const locale = I18n.locale();
        for (let i = 0; i < 7; i++) {
            const qtDay = ((firstDayOfWeek + i + 6) % 7) + 1;
            names.push(locale.dayName(qtDay, Locale.ShortFormat));
        }
        return names;
    }

    implicitHeight: calendarExpanded ? expandedHeight : collapsedHeight
    height: implicitHeight
    radius: Theme.cornerRadiusL
    color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
    border.width: Theme.layerOutlineWidth
    border.color: Theme.outlineVariant
    clip: true

    function sameDay(left, right) {
        return left.getFullYear() === right.getFullYear() && left.getMonth() === right.getMonth() && left.getDate() === right.getDate();
    }

    function selectDay(date) {
        selectedDate = date;
        userSelectedDate = true;
        userBrowsingCalendar = false;
        if (date.getMonth() !== displayDate.getMonth() || date.getFullYear() !== displayDate.getFullYear())
            displayDate = date;
    }

    function shiftMonth(delta) {
        displayDate = new Date(displayDate.getFullYear(), displayDate.getMonth() + delta, 1, 12);
        userBrowsingCalendar = true;
    }

    function goToToday() {
        userSelectedDate = false;
        userBrowsingCalendar = false;
        selectedDate = currentDate;
        displayDate = currentDate;
    }

    onCurrentDateChanged: {
        if (userSelectedDate || userBrowsingCalendar)
            return;
        selectedDate = currentDate;
        displayDate = currentDate;
    }

    SystemClock {
        id: systemClock
        precision: SystemClock.Minutes
    }

    Item {
        id: dateRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: root.panelPadding
        anchors.rightMargin: root.panelPadding
        anchors.topMargin: root.panelPadding
        height: root.dateRowHeight

        StyledText {
            anchors.left: parent.left
            anchors.right: collapseButton.left
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: root.selectedDate.toLocaleDateString(I18n.locale(), "dddd, MMMM d")
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
            elide: Text.ElideRight
        }

        CyActionButton {
            id: collapseButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: Theme.buttonHeightXS
            iconName: root.calendarExpanded ? "expand_more" : "expand_less"
            iconColor: Theme.onSurfaceVariant
            backgroundColor: Theme.secondaryContainer
            tooltipText: root.calendarExpanded ? I18n.tr("Collapse calendar") : I18n.tr("Expand calendar")
            onClicked: root.calendarExpanded = !root.calendarExpanded
        }
    }

    Item {
        id: monthRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: dateRow.bottom
        anchors.leftMargin: root.panelPadding
        anchors.rightMargin: root.panelPadding
        anchors.topMargin: Theme.spacingS
        height: Theme.buttonHeightS
        visible: root.calendarExpanded

        StyledText {
            anchors.left: parent.left
            anchors.right: monthActions.left
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: root.displayDate.toLocaleDateString(I18n.locale(), "MMMM yyyy")
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
            elide: Text.ElideRight
        }

        Row {
            id: monthActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS

            CyActionButton {
                buttonSize: Theme.buttonHeightXS
                iconName: "today"
                tooltipText: I18n.tr("Today")
                enabled: !root.sameDay(root.selectedDate, root.currentDate) || root.displayDate.getMonth() !== root.currentDate.getMonth() || root.displayDate.getFullYear() !== root.currentDate.getFullYear()
                onClicked: root.goToToday()
            }

            CyActionButton {
                buttonSize: Theme.buttonHeightXS
                iconName: I18n.isRtl ? "chevron_right" : "chevron_left"
                tooltipText: I18n.tr("Previous month")
                onClicked: root.shiftMonth(-1)
            }

            CyActionButton {
                buttonSize: Theme.buttonHeightXS
                iconName: I18n.isRtl ? "chevron_left" : "chevron_right"
                tooltipText: I18n.tr("Next month")
                onClicked: root.shiftMonth(1)
            }
        }
    }

    CyMonthGrid {
        id: monthGrid
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: monthRow.bottom
        anchors.bottom: focusDivider.top
        anchors.leftMargin: root.panelPadding
        anchors.rightMargin: root.panelPadding
        anchors.topMargin: Theme.spacingS
        anchors.bottomMargin: Theme.spacingS
        visible: root.calendarExpanded
        displayDate: root.displayDate
        selectedDate: root.selectedDate
        today: root.currentDate
        firstDayOfWeek: root.firstDayOfWeek
        dayNames: root.weekdayNames
        showWeekNumbers: false
        weekdayRowHeight: Theme.buttonHeightXS
        cellGap: Theme.spacingXS
        cellRadius: Theme.buttonHeightXS / 2
        transparentUnselectedCells: true
        centerDayNumbers: true
        onDayClicked: date => root.selectDay(date)
    }

    Rectangle {
        id: focusDivider
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: focusRow.top
        anchors.leftMargin: root.panelPadding
        anchors.rightMargin: root.panelPadding
        height: Theme.dividerWidth
        color: Theme.outlineVariant
        visible: root.calendarExpanded
    }

    Row {
        id: focusRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.panelPadding
        anchors.rightMargin: root.panelPadding
        anchors.bottomMargin: root.panelPadding
        height: root.focusRowHeight
        spacing: Theme.spacingS

        CyActionButton {
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: Theme.buttonHeightXS
            iconName: "remove"
            tooltipText: I18n.tr("Decrease focus duration")
            enabled: !root.focusSessionActive
            onClicked: root.focusMinutes = Math.max(5, root.focusMinutes - 5)
        }

        StyledText {
            id: focusDuration
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.duration((root.focusSessionActive ? root.remainingFocusMinutes : root.focusMinutes) * 60)
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceText
        }

        CyActionButton {
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: Theme.buttonHeightXS
            iconName: "add"
            tooltipText: I18n.tr("Increase focus duration")
            enabled: !root.focusSessionActive
            onClicked: root.focusMinutes = Math.min(120, root.focusMinutes + 5)
        }

        Item {
            width: Math.max(0, parent.width - Theme.buttonHeightXS * 2 - focusDuration.implicitWidth - Theme.spacingS * 4 - focusButton.implicitWidth)
            height: 1
        }

        CyButton {
            id: focusButton
            anchors.verticalCenter: parent.verticalCenter
            buttonHeight: Theme.buttonHeightXS
            iconName: root.focusSessionActive ? "stop" : "play_arrow"
            text: root.focusSessionActive ? I18n.tr("End focus") : I18n.tr("Focus")
            backgroundColor: root.focusSessionActive ? Theme.primaryContainer : Theme.secondaryContainer
            textColor: root.focusSessionActive ? Theme.onPrimaryContainer : Theme.onSecondaryContainer
            onClicked: {
                if (root.focusSessionActive) {
                    SessionData.setDoNotDisturb(false);
                    return;
                }
                SessionData.setDoNotDisturb(true, root.focusMinutes);
                ToastService.showInfo(I18n.tr("Focus session started"), I18n.duration(root.focusMinutes * 60));
                root.focusSessionStarted(root.focusMinutes);
            }
        }
    }
}
