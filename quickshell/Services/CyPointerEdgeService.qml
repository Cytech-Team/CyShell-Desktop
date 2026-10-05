import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false
    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/cytech-pointer-edge"

    function setEdge(enabled, strength) {
        const s = Math.max(1, Math.min(200, Number(strength) || 30));
        Quickshell.execDetached([root.helper, "set", "--enabled", enabled ? "true" : "false", "--resistance", String(Math.round(s))]);
    }

    IpcHandler {
        target: "cytech-pointer-edge"
        function enable(strength: int): string {
            root.setEdge(true, strength > 0 ? strength : 30);
            return "enabled";
        }
        function disable(): string {
            root.setEdge(false, 30);
            return "disabled";
        }
        function set(strength: int): string {
            root.setEdge(true, strength);
            return "set";
        }
    }

    Component.onCompleted: console.info("CyPointerEdgeService: native CyShell service loaded")
}
