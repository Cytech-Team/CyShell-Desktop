import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.Services
import qs.Widgets

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property bool editMode: false
    property bool tapToClose: false
    property bool live: true

    signal powerButtonClicked
    signal lockRequested
    signal editModeToggled
    signal editCancelled
    signal settingsButtonClicked
    signal headerTapped

    Ref {
        service: DgopService
        modules: "system"
        active: root.live && root.visible && (root.Window.window?.visible ?? false)
    }

    implicitHeight: CcMetrics.headerHeight
    height: implicitHeight

    MouseArea {
        anchors.fill: parent
        enabled: root.tapToClose
        acceptedButtons: Qt.LeftButton
        onClicked: root.headerTapped()
    }

    Item {
        anchors.left: parent.left
        anchors.right: actionButtonsRow.left
        anchors.rightMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height

        property date now: new Date()

        Timer {
            interval: 30000
            repeat: true
            running: root.visible
            triggeredOnStart: true
            onTriggered: parent.now = new Date()
        }

        StyledText {
            id: timeLabel
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.topMargin: 4
            text: Qt.formatTime(parent.now, "h:mm AP")
            font.pixelSize: Theme.fontSizeXXLarge
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
        }

        StyledText {
            anchors.left: parent.left
            anchors.top: timeLabel.bottom
            anchors.topMargin: 2
            text: Qt.formatDate(parent.now, "ddd, MMM d")
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
        }
    }

    Row {
        id: actionButtonsRow
        height: CcMetrics.headerActionSize
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingS

        CyActionButton {
            buttonSize: CcMetrics.headerActionSize
            iconSize: CcMetrics.headerActionIconSize
            iconName: "monitor"
            iconColor: Theme.surfaceText
            backgroundColor: Theme.withAlpha(Theme.surfaceContainerHigh, 0.88)
            Accessible.name: I18n.tr("Display")
            onClicked: root.settingsButtonClicked()
        }

        CyActionButton {
            buttonSize: CcMetrics.headerActionSize
            iconSize: CcMetrics.headerActionIconSize
            iconName: "power_settings_new"
            iconColor: Theme.surfaceText
            backgroundColor: Theme.withAlpha(Theme.surfaceContainerHigh, 0.88)
            Accessible.name: I18n.tr("Power")
            onClicked: root.powerButtonClicked()
        }
    }

}
