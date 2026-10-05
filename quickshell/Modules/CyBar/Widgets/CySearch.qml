import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    property var popoutService: null

    pillClickAction: () => popoutService?.toggleDankLauncherV2()
    pillRightClickAction: () => Quickshell.execDetached(["cyshell", "ipc", "call", "processlist", "toggle"])

    horizontalBarPill: Component {
        Item {
            implicitWidth: 30
            implicitHeight: 32
            CyIcon {
                anchors.centerIn: parent
                name: "search"
                size: 22
                color: Theme.widgetTextColor
            }
        }
    }

    verticalBarPill: horizontalBarPill
}
