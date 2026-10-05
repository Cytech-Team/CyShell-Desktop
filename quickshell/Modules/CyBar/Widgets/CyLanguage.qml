import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    Component.onCompleted: KeyboardLayoutService.consumers++
    Component.onDestruction: KeyboardLayoutService.consumers--

    pillClickAction: () => KeyboardLayoutService.cycle()

    horizontalBarPill: Component {
        Item {
            implicitWidth: 26
            implicitHeight: 30
            StyledText {
                anchors.centerIn: parent
                text: KeyboardLayoutService.currentLayout === "th" ? "TH" : "US"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                color: Theme.widgetTextColor
            }
        }
    }
    verticalBarPill: horizontalBarPill
}
