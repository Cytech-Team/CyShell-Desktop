import QtQuick
import Quickshell
import Quickshell.Io
import qs.Modules.ScreenEdges

ShellRoot {
    id: root

    property bool surfacesLoaded: true

    function refreshSurfaces() {
        surfacesLoaded = false;
        reloadTimer.restart();
    }

    Timer {
        id: reloadTimer
        interval: 1
        repeat: false
        onTriggered: root.surfacesLoaded = true
    }

    Loader {
        active: root.surfacesLoaded
        asynchronous: false
        sourceComponent: ScreenEdges {}
    }

    IpcHandler {
        target: "surfaces"

        function refresh(): string {
            root.refreshSurfaces();
            return "SURFACES_REFRESHED";
        }
    }
}
