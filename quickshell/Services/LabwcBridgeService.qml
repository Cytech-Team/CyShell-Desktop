pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

Singleton {
    id: root

    readonly property var log: Log.scoped("LabwcBridgeService")
    readonly property string socketPath: {
        const runtime = Quickshell.env("XDG_RUNTIME_DIR") || "";
        return runtime ? runtime + "/cyshell-labwc.sock" : "";
    }

    property bool connected: false
    property int apiVersion: 0
    property string labwcVersion: ""
    property string wlrootsVersion: ""
    property int compositorPid: 0
    property var capabilities: []
    property var windows: []
    property string lastError: ""

    signal bridgeStateChanged
    signal windowsRefreshed

    Component.onCompleted: {
        if (socketPath)
            requestSocket.connected = true;
    }

    function refresh() {
        if (!requestSocket.linkUp)
            return;
        requestSocket.send({"method": "status"});
        requestSocket.send({"method": "windows.list"});
    }

    function refreshWindows() {
        if (requestSocket.linkUp)
            requestSocket.send({"method": "windows.list"});
    }

    function closeWindow(id) {
        if (!requestSocket.linkUp || !id)
            return false;
        requestSocket.send({
            "method": "window.close",
            "id": String(id)
        });
        return true;
    }

    function _handleResponse(line) {
        if (!line || line.length === 0)
            return;

        let message;
        try {
            message = JSON.parse(line);
        } catch (e) {
            log.warn("Invalid bridge response:", line.substring(0, 160));
            return;
        }

        if (message.ok === false) {
            lastError = String(message.error || "LabWC bridge request failed");
            return;
        }

        if (message.name === "CyShell LabWC Bridge") {
            apiVersion = Number(message.api || 0);
            labwcVersion = String(message.labwcVersion || "");
            wlrootsVersion = String(message.wlrootsVersion || "");
            compositorPid = Number(message.pid || 0);
            capabilities = Array.isArray(message.capabilities) ? message.capabilities : [];
            lastError = "";
            bridgeStateChanged();
        }

        if (Array.isArray(message.windows)) {
            windows = message.windows;
            windowsRefreshed();
        }
    }

    CySocket {
        id: requestSocket
        path: root.socketPath
        connected: false
        reconnectBaseMs: 250
        reconnectMaxMs: 5000

        onConnectionStateChanged: {
            root.connected = linkUp;
            if (linkUp) {
                root.lastError = "";
                root.refresh();
                eventSocket.connected = true;
            } else {
                root.apiVersion = 0;
                root.capabilities = [];
                root.compositorPid = 0;
                root.windows = [];
                eventSocket.connected = false;
            }
            root.bridgeStateChanged();
        }

        parser: SplitParser {
            onRead: line => root._handleResponse(line)
        }
    }

    CySocket {
        id: eventSocket
        path: root.socketPath
        connected: false
        reconnectBaseMs: 250
        reconnectMaxMs: 5000

        onConnectionStateChanged: {
            if (linkUp)
                send({"method": "events.subscribe"});
        }

        parser: SplitParser {
            onRead: line => {
                if (!line || line.length === 0)
                    return;

                let message;
                try {
                    message = JSON.parse(line);
                } catch (e) {
                    return;
                }

                if (message.event && String(message.event).startsWith("window."))
                    windowRefreshDebounce.restart();
            }
        }
    }

    Timer {
        id: windowRefreshDebounce
        interval: 30
        repeat: false
        onTriggered: root.refreshWindows()
    }
}
