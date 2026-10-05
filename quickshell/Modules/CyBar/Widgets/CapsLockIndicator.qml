import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

BasePill {
    id: root

    opacity: CyShellService.capsLockState ? 1 : 0

    states: [
        State {
            name: "hidden_horizontal"
            when: !CyShellService.capsLockState && !isVerticalOrientation
            PropertyChanges {
                target: root
                width: 0
            }
        },
        State {
            name: "hidden_vertical"
            when: !CyShellService.capsLockState && isVerticalOrientation
            PropertyChanges {
                target: root
                height: 0
            }
        }
    ]

    transitions: [
        Transition {
            NumberAnimation {
                properties: "width,height"
                duration: Theme.shortDuration
                easing.type: Theme.standardEasing
            }
        }
    ]

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Theme.standardEasing
        }
    }

    content: Component {
        Item {
            implicitWidth: icon.width
            implicitHeight: root.contentThickness

            CyIcon {
                id: icon
                anchors.centerIn: parent
                name: "shift_lock"
                size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                color: Theme.primary
            }
        }
    }
}
