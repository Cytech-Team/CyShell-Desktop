import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// LabWC owns Alt+Tab/Alt+Shift+Tab, window ordering, thumbnails and preview.
// CyShell only adds a small action strip for the currently selected/focused
// toplevel; it never draws a second switcher or performs the window cycle.
Item {
    id: root

    property bool shown: false
    property var selectedWindow: null
    property var targetScreen: null
    property int _lastAltTabSerial: CyShellService.altTabSerial
    property bool _ready: false

    Component.onCompleted: {
        _lastAltTabSerial = CyShellService.altTabSerial;
        _ready = true;
    }

    function currentActiveWindow() {
        const list = Array.from(ToplevelManager.toplevels?.values || []);
        for (const win of list) {
            if (win && win.activated)
                return win;
        }
        return null;
    }

    function refreshSelection() {
        const active = currentActiveWindow();
        if (active)
            selectedWindow = active;
        targetScreen = CompositorService.getFocusedScreen() || Quickshell.screens[0] || null;
    }

    function showControls() {
        refreshSelection();
        shown = true;
        selectionPoll.restart();
        hideTimer.restart();
        return "LABWC_SWITCHER_CONTROLS_SHOWN";
    }

    function closeSelected() {
        // Resolve again at click time. LabWC may only commit the selected
        // window when Alt is released, so this always targets its final choice.
        const win = currentActiveWindow() || selectedWindow;
        if (!win)
            return "WINDOW_SWITCHER_NO_SELECTION";
        win.close();
        shown = false;
        return "WINDOW_SWITCHER_CLOSE_SUCCESS";
    }

    Connections {
        target: CyShellService

        function onConnectionStateChanged() {
            if (!CyShellService.isConnected)
                return;
            root._lastAltTabSerial = CyShellService.altTabSerial;
            root._ready = true;
        }

        function onAltTabSerialChanged() {
            const serial = CyShellService.altTabSerial;
            if (!root._ready) {
                root._lastAltTabSerial = serial;
                root._ready = true;
                return;
            }
            if (serial === root._lastAltTabSerial)
                return;
            root._lastAltTabSerial = serial;
            // LabWC receives the same physical key first/alongside us. A short
            // delay lets its native selection/preview settle before we mirror
            // only the action target.
            nativeSettle.restart();
        }
    }

    Timer {
        id: nativeSettle
        interval: 70
        repeat: false
        onTriggered: root.showControls()
    }

    Timer {
        id: selectionPoll
        interval: 80
        repeat: true
        onTriggered: {
            if (!root.shown) {
                stop();
                return;
            }
            root.refreshSelection();
        }
    }

    Timer {
        id: hideTimer
        interval: 1800
        repeat: false
        onTriggered: {
            root.shown = false;
            selectionPoll.stop();
        }
    }

    IpcHandler {
        target: "window-switcher"

        function show(): string {
            return root.showControls();
        }

        function close(): string {
            return root.closeSelected();
        }

        function hide(): string {
            root.shown = false;
            selectionPoll.stop();
            return "WINDOW_SWITCHER_HIDE_SUCCESS";
        }
    }

    PanelWindow {
        id: overlay

        visible: root.shown && root.selectedWindow
        screen: root.targetScreen || Quickshell.screens[0] || null
        color: "transparent"

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        WlrLayershell.namespace: "cyshell:labwc-switcher-controls"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        mask: Region {
            item: actionStrip
        }

        Rectangle {
            id: actionStrip

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 150

            width: Math.min(460, Math.max(190, titleText.implicitWidth + closeButton.width + Theme.spacingL * 3))
            height: 46
            radius: Theme.cornerRadiusM
            color: Theme.withAlpha(Theme.floatingSurface, 0.96)
            border.width: Theme.dividerWidth
            border.color: Theme.outlineVariant

            StyledText {
                id: titleText
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingM
                anchors.right: closeButton.left
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                text: root.selectedWindow?.title || root.selectedWindow?.appId || I18n.tr("Window")
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
            }

            Rectangle {
                id: closeButton

                width: 34
                height: 34
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.fullRadius(width, height)
                color: closeMouse.containsMouse ? Theme.errorContainer : Theme.surfaceContainerHigh

                CyIcon {
                    anchors.centerIn: parent
                    name: "close"
                    size: 19
                    color: closeMouse.containsMouse ? Theme.onErrorContainer : Theme.surfaceText
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.closeSelected();
                        hideTimer.stop();
                        selectionPoll.stop();
                    }
                }
            }
        }
    }
}
