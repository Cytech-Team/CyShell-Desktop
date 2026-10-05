import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

Variants {
    id: root

    readonly property var edgeTargets: {
        void Quickshell.screens;
        const out = [];
        for (const screen of (Quickshell.screens || [])) {
            if (!screen || String(screen.name || "").startsWith("HEADLESS-"))
                continue;
            for (const edge of ["left", "right", "top", "bottom"])
                out.push({ screen: screen, edge: edge });
        }
        return out;
    }

    model: root.edgeTargets

    function actionFor(edge) {
        switch (edge) {
        case "left": return SettingsData.screenEdgeLeftAction;
        case "right": return SettingsData.screenEdgeRightAction;
        case "top": return SettingsData.screenEdgeTopAction;
        case "bottom": return SettingsData.screenEdgeBottomAction;
        default: return "none";
        }
    }

    function trigger(action) {
        switch (String(action || "none")) {
        case "launcher":
            Quickshell.execDetached(["/usr/local/bin/cyshell", "ipc", "call", "launcher", "toggle"]);
            break;
        case "control-center":
            Quickshell.execDetached(["/usr/local/bin/cyshell", "ipc", "call", "control-center", "toggle"]);
            break;
        case "settings":
            Quickshell.execDetached(["/usr/local/bin/cyshell", "ipc", "call", "settings", "focusOrToggle"]);
            break;
        case "process-list":
            Quickshell.execDetached(["/usr/local/bin/cyshell", "ipc", "call", "processlist", "toggle"]);
            break;
        }
    }

    delegate: PanelWindow {
        id: edgeWindow

        required property var modelData
        readonly property string edge: String(modelData?.edge || "")
        readonly property string action: root.actionFor(edge)
        readonly property bool vertical: edge === "left" || edge === "right"
        property bool armed: true

        screen: modelData?.screen || null
        visible: SettingsData.screenEdgesEnabled && action !== "none"
        color: "transparent"

        anchors.left: edge === "left" || !vertical
        anchors.right: edge === "right" || !vertical
        anchors.top: edge === "top" || vertical
        anchors.bottom: edge === "bottom" || vertical

        implicitWidth: vertical ? Math.max(1, SettingsData.screenEdgeThickness) : 1
        implicitHeight: vertical ? 1 : Math.max(1, SettingsData.screenEdgeThickness)

        WlrLayershell.namespace: "cyshell:screen-edge:" + edge
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Timer {
            id: rearmTimer
            interval: 700
            repeat: false
            onTriggered: edgeWindow.armed = true
        }

        HoverHandler {
            id: edgeHover
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onHoveredChanged: {
                if (!hovered || !edgeWindow.armed)
                    return;
                edgeWindow.armed = false;
                root.trigger(edgeWindow.action);
                rearmTimer.restart();
            }
        }
    }
}
