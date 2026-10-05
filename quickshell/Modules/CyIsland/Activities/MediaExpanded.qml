pragma ComponentBehavior: Bound

import QtQuick
import qs.Modules.CyDash

DashTabFace {
    id: root

    activityId: "media"
    tabComponent: Component {
        MediaPlayerTab {
            live: root.live
        }
    }
}
