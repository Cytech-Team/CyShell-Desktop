pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("ExtWorkspaceService")

    property bool available: false
    property var workspaces: []
    property var groups: []
    signal stateChanged

    Connections {
        target: DMSService

        function onCapabilitiesReceived() {
            root.checkCapabilities();
        }

        function onConnectionStateChanged() {
            if (DMSService.isConnected) {
                root.checkCapabilities();
                return;
            }
            root.available = false;
            root.workspaces = [];
            root.groups = [];
            root.stateChanged();
        }

        function onWorkspaceStateUpdate(data) {
            root.applyState(data);
        }
    }

    Component.onCompleted: {
        if (DMSService.dmsAvailable)
            checkCapabilities();
    }

    function checkCapabilities() {
        const caps = DMSService.capabilities || [];
        if (!Array.isArray(caps) || !caps.includes("workspace")) {
            available = false;
            return;
        }
        requestState();
    }

    function requestState() {
        if (!DMSService.isConnected)
            return;
        DMSService.sendRequest("workspace.getState", null, response => {
            if (response.error || !response.result) {
                log.debug("workspace.getState unavailable:", response.error || "empty result");
                return;
            }
            applyState(response.result);
        });
    }

    function applyState(state) {
        available = state?.available === true;
        workspaces = state?.workspaces || [];
        groups = state?.groups || [];
        stateChanged();
    }

    function activeWorkspace(outputName) {
        const visible = workspaces.filter(ws => !ws.hidden && ws.active);
        if (!outputName)
            return visible.length > 0 ? visible[0] : null;
        const group = groups.find(g => (g.outputs || []).includes(outputName));
        if (!group)
            return visible.length > 0 ? visible[0] : null;
        return visible.find(ws => ws.groupId === group.objectId) || null;
    }

    function workspacesForOutput(outputName) {
        if (!outputName)
            return workspaces.filter(ws => !ws.hidden);
        const group = groups.find(g => (g.outputs || []).includes(outputName));
        if (!group)
            return workspaces.filter(ws => !ws.hidden);
        return workspaces.filter(ws => ws.groupId === group.objectId && !ws.hidden);
    }

    function activate(selector, callback) {
        if (!DMSService.isConnected || !available) {
            if (callback)
                callback(false, "Workspace API unavailable");
            return;
        }
        DMSService.sendRequest("workspace.activate", {
            workspace: String(selector)
        }, response => {
            const success = !response.error && response.result?.success === true;
            if (!success)
                log.warn("workspace activation failed:", response.error || response.result?.message || "unknown error");
            if (callback)
                callback(success, response.error || response.result?.message || "");
        });
    }
}
