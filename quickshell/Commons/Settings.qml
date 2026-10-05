pragma Singleton
import QtQuick
import Quickshell
import qs.Common

Singleton {
    readonly property var data: ({
        "colorSchemes": { "darkMode": !Theme.isLightMode },
        "systemMonitor": { "externalMonitor": "btop" }
    })
    function getBarPositionForScreen(screenName) { return "top"; }
}
