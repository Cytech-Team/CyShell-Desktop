import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

CyOSD {
    id: root

    osdWidth: Theme.osdHeight
    osdHeight: Theme.osdHeight
    autoHideInterval: 1600
    enableMouseInteraction: false

    property string lastLayout: ""

    Connections {
        target: KeyboardLayoutService
        function onCurrentLayoutChanged() {
            if (!KeyboardLayoutService.layoutKnown)
                return;
            if (lastLayout !== "" && lastLayout !== KeyboardLayoutService.currentLayout)
                root.show();
            lastLayout = KeyboardLayoutService.currentLayout;
        }
    }

    Component.onCompleted: {
        KeyboardLayoutService.consumers++;
        lastLayout = KeyboardLayoutService.currentLayout;
    }
    Component.onDestruction: KeyboardLayoutService.consumers--

    content: Item {
        Column {
            anchors.centerIn: parent
            spacing: 2
            CyIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "keyboard"
                size: 24
                color: Theme.primary
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: KeyboardLayoutService.currentLayout === "th" ? "TH" : "US"
                font.pixelSize: 13
                font.weight: Font.Bold
                color: Theme.surfaceText
            }
        }
    }
}
