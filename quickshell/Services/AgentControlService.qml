pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("AgentControlService")

    property bool available: false
    property bool embedded: false
    property bool enabled: false
    property bool controlEnabled: false
    property int toolCount: 0
    property int activeCalls: 0
    property var permissions: []
    property var appPolicies: []
    property int pendingApprovalCount: 0
    property string version: ""
    property string stateDir: ""
    property string lastError: ""
    property bool busy: false
    property var recentActivity: []
    property var actionReceipts: []
    readonly property var lastActivity: recentActivity.length > 0 ? recentActivity[0] : null

    signal stateChanged
    signal activityChanged
    signal receiptsChanged
    signal emergencyStopped

    Connections {
        target: DMSService
        function onCapabilitiesReceived() {
            root.refresh();
            root.refreshActivity();
            root.refreshReceipts();
        }
        function onAgentEvent(data) {
            root.applyEvent(data);
        }
        function onConnectionStateChanged() {
            if (DMSService.isConnected) {
                root.refresh();
                root.refreshActivity();
                root.refreshReceipts();
                return;
            }
            root.available = false;
            root.embedded = false;
            root.enabled = false;
            root.controlEnabled = false;
            root.activeCalls = 0;
            root.permissions = [];
            root.appPolicies = [];
            root.pendingApprovalCount = 0;
            root.recentActivity = [];
            root.actionReceipts = [];
            root.stateChanged();
            root.activityChanged();
            root.receiptsChanged();
        }
    }

    Component.onCompleted: {
        refresh();
        refreshActivity();
        refreshReceipts();
    }

    function applyState(state) {
        available = true;
        embedded = state?.embedded === true;
        enabled = state?.enabled === true;
        controlEnabled = state?.controlEnabled === true;
        toolCount = Number(state?.toolCount || 0);
        activeCalls = Number(state?.activeCalls || 0);
        permissions = Array.isArray(state?.permissions) ? state.permissions : [];
        appPolicies = Array.isArray(state?.appPolicies) ? state.appPolicies : [];
        pendingApprovalCount = Number(state?.pendingApprovalCount || 0);
        version = String(state?.version || "");
        stateDir = String(state?.stateDir || "");
        lastError = "";
        stateChanged();
    }

    function applyEvent(data) {
        if (!data)
            return;
        if (data.state)
            applyState(data.state);
        if (Array.isArray(data.recentActivity)) {
            recentActivity = data.recentActivity.slice(0, 64);
            activityChanged();
        }
        if (Array.isArray(data.actionReceipts)) {
            actionReceipts = data.actionReceipts;
            receiptsChanged();
        }
        if (data.activity)
            upsertActivity(data.activity);
    }

    function upsertActivity(activity) {
        const id = String(activity?.id || "");
        if (!id)
            return;
        const next = recentActivity.filter(item => String(item?.id || "") !== id);
        next.unshift(activity);
        next.sort((a, b) => Number(b?.startedAt || 0) - Number(a?.startedAt || 0));
        recentActivity = next.slice(0, 64);
        activityChanged();
    }

    function refresh(callback) {
        if (!DMSService.isConnected || !(DMSService.capabilities || []).includes("cycom")) {
            available = false;
            if (callback)
                callback(false, "CyCom runtime unavailable");
            return;
        }
        DMSService.sendRequest("cycom.getRuntimeState", null, response => {
            if (response.error || !response.result) {
                available = false;
                lastError = response.error || "CyCom state unavailable";
                stateChanged();
                if (callback)
                    callback(false, lastError);
                return;
            }
            applyState(response.result);
            if (callback)
                callback(true, "");
        });
    }

    function refreshActivity(callback) {
        if (!DMSService.isConnected || !(DMSService.capabilities || []).includes("cycom")) {
            if (callback)
                callback(false, "CyCom runtime unavailable");
            return;
        }
        DMSService.sendRequest("cycom.activity.list", null, response => {
            if (response.error) {
                if (callback)
                    callback(false, response.error);
                return;
            }
            recentActivity = Array.isArray(response.result) ? response.result.slice(0, 64) : [];
            activityChanged();
            if (callback)
                callback(true, "");
        });
    }

    function clearActivity(callback) {
        DMSService.sendRequest("cycom.activity.clear", null, response => {
            if (response.error) {
                lastError = response.error;
                if (callback)
                    callback(false, lastError);
                return;
            }
            recentActivity = [];
            activityChanged();
            if (callback)
                callback(true, "");
        });
    }

    function refreshReceipts(callback) {
        if (!DMSService.isConnected || !(DMSService.capabilities || []).includes("cycom")) {
            if (callback)
                callback(false, "CyCom runtime unavailable");
            return;
        }
        DMSService.sendRequest("cycom.receipts.list", null, response => {
            if (response.error) {
                if (callback)
                    callback(false, response.error);
                return;
            }
            actionReceipts = Array.isArray(response.result) ? response.result : [];
            receiptsChanged();
            if (callback)
                callback(true, "");
        });
    }

    function undoReceipt(receiptId, callback) {
        const id = String(receiptId || "").trim();
        if (!id) {
            if (callback)
                callback(false, I18n.tr("Action receipt is missing"));
            return;
        }
        DMSService.sendRequest("cycom.tools.call", {
            name: "desktop_undo",
            reason: "User requested rollback from CyShell Agent Settings",
            arguments: { receipt: id },
            origin: { kind: "ui", name: "CyShell Settings" }
        }, response => {
            if (response.error) {
                lastError = response.error;
                if (callback)
                    callback(false, lastError);
                return;
            }
            refreshReceipts();
            if (callback)
                callback(true, "");
        }, 30000);
    }

    function setEnabled(value, callback) {
        if (busy)
            return;
        busy = true;
        DMSService.sendRequest("cycom.setEnabled", { enabled: !!value }, response => {
            busy = false;
            if (response.error || !response.result) {
                lastError = response.error || "Failed to update Agent state";
                if (callback)
                    callback(false, lastError);
                return;
            }
            applyState(response.result);
            if (callback)
                callback(true, "");
        });
    }

    function setControlEnabled(value, callback) {
        if (busy)
            return;
        busy = true;
        DMSService.sendRequest("cycom.setControlEnabled", { enabled: !!value }, response => {
            busy = false;
            if (response.error || !response.result) {
                lastError = response.error || "Failed to update Agent control state";
                if (callback)
                    callback(false, lastError);
                return;
            }
            applyState(response.result);
            if (callback)
                callback(true, "");
        });
    }

    function setPermission(scope, value, callback) {
        if (busy)
            return;
        busy = true;
        DMSService.sendRequest("cycom.setPermission", { scope: String(scope), enabled: !!value }, response => {
            busy = false;
            if (response.error || !response.result) {
                lastError = response.error || "Failed to update Agent permission";
                if (callback)
                    callback(false, lastError);
                return;
            }
            applyState(response.result);
            if (callback)
                callback(true, "");
        });
    }

    function permission(scope) {
        return permissions.find(item => String(item?.id || "") === String(scope)) || null;
    }

    function emergencyStop(callback) {
        if (busy)
            return;
        busy = true;
        DMSService.sendRequest("cycom.emergencyStop", null, response => {
            busy = false;
            if (response.error || !response.result) {
                lastError = response.error || "Emergency stop failed";
                if (callback)
                    callback(false, lastError);
                return;
            }
            applyState(response.result);
            emergencyStopped();
            if (callback)
                callback(true, "");
        });
    }
}
