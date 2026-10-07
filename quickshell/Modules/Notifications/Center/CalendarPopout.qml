import QtQuick
import qs.Common
import qs.Modules.Notifications
import qs.Services
import qs.Widgets

CyPopout {
    id: root

    layerNamespace: "cyshell:calendar-popout"
    fullHeightSurface: true
    positioning: ""
    popupWidth: NotificationMetrics.popupMinWidth + Theme.spacingL
    popupHeight: contentLoader.item ? Theme.px(contentLoader.item.implicitHeight, dpr) : Theme.px(Theme.buttonHeightM * 8, dpr)
    popupEdgeGap: Theme.spacingM
    screen: triggerScreen

    property var triggerScreen: null

    onBackgroundClicked: close()

    content: Component {
        Item {
            implicitWidth: root.popupWidth
            implicitHeight: calendar.implicitHeight

            NotificationCalendar {
                id: calendar
                width: parent.width
                expandedHeight: Theme.buttonHeightM * 8
                onFocusSessionStarted: root.close()
            }
        }
    }
}
