import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

CyOSD {
    id: root

    osdWidth: Theme.osdHeight
    osdHeight: Theme.osdHeight
    autoHideInterval: 2000
    enableMouseInteraction: false

    property bool lastCapsLockState: false

    Connections {
        target: CyShellService

        function onCapsLockStateChanged() {
            if (lastCapsLockState !== CyShellService.capsLockState && SettingsData.osdCapsLockEnabled) {
                root.show();
            }
            lastCapsLockState = CyShellService.capsLockState;
        }
    }

    Component.onCompleted: {
        lastCapsLockState = CyShellService.capsLockState;
    }

    content: Item {
        OsdIcon {
            tonal: false
            anchors.centerIn: parent
            iconName: CyShellService.capsLockState ? "shift_lock" : "shift_lock_off"
            iconColor: Theme.primary
        }
    }
}
