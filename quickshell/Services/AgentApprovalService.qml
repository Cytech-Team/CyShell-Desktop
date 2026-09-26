pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("AgentApprovalService")

    property var pendingApprovals: []
    property var appPolicies: []
    property bool refreshing: false
    property bool responding: false
    property string lastError: ""
    property string lastPresentedId: ""

    readonly property int pendingCount: pendingApprovals.length
    readonly property var currentApproval: pendingCount > 0 ? pendingApprovals[0] : null

    signal pendingChanged
    signal policiesChanged

    Connections {
        target: DMSService
        function onCapabilitiesReceived() {
            root.refresh();
            root.refreshPolicies();
        }
        function onAgentEvent(data) {
            root.applyEvent(data);
        }
        function onConnectionStateChanged() {
            if (DMSService.isConnected) {
                root.refresh();
                root.refreshPolicies();
                return;
            }
            root.pendingApprovals = [];
            root.appPolicies = [];
            root.lastPresentedId = "";
            root.pendingChanged();
            root.policiesChanged();
        }
    }

    function applyPending(next) {
        pendingApprovals = Array.isArray(next) ? next : [];
        lastError = "";
        pendingChanged();
        const current = pendingApprovals.length > 0 ? pendingApprovals[0] : null;
        if (current && String(current.id || "") !== lastPresentedId) {
            lastPresentedId = String(current.id || "");
            PopoutService.showAgentApproval();
        } else if (!current) {
            lastPresentedId = "";
            PopoutService.hideAgentApproval();
        }
    }

    function applyEvent(data) {
        if (!data)
            return;
        if (data.pendingApprovals !== undefined)
            applyPending(data.pendingApprovals);
        if (data.state && Array.isArray(data.state.appPolicies)) {
            appPolicies = data.state.appPolicies;
            policiesChanged();
        }
    }

    function refresh() {
        if (refreshing || !DMSService.isConnected || !(DMSService.capabilities || []).includes("cycom"))
            return;
        refreshing = true;
        DMSService.sendRequest("cycom.approvals.list", null, response => {
            refreshing = false;
            if (response.error) {
                lastError = response.error;
                return;
            }
            root.applyPending(Array.isArray(response.result) ? response.result : []);
        });
    }

    function refreshPolicies(callback) {
        if (!DMSService.isConnected || !(DMSService.capabilities || []).includes("cycom")) {
            if (callback)
                callback(false, I18n.tr("CyCom runtime unavailable"));
            return;
        }
        DMSService.sendRequest("cycom.appPolicies.list", null, response => {
            if (response.error) {
                lastError = response.error;
                if (callback)
                    callback(false, lastError);
                return;
            }
            appPolicies = Array.isArray(response.result) ? response.result : [];
            policiesChanged();
            if (callback)
                callback(true, "");
        });
    }

    function respond(decision, callback) {
        const approval = currentApproval;
        if (!approval || responding)
            return;
        responding = true;
        DMSService.sendRequest("cycom.approval.respond", {
            id: String(approval.id || ""),
            decision: String(decision || "")
        }, response => {
            responding = false;
            if (response.error) {
                lastError = response.error;
                if (callback)
                    callback(false, lastError);
                refresh();
                return;
            }
            lastError = "";
            if (decision === "allow_always" || decision === "deny_always")
                refreshPolicies();
            refresh();
            if (callback)
                callback(true, "");
        });
    }

    function setPolicy(appKey, appName, scope, mode, callback) {
        DMSService.sendRequest("cycom.appPolicy.set", {
            appKey: String(appKey || ""),
            appName: String(appName || ""),
            scope: String(scope || ""),
            mode: String(mode || "ask")
        }, response => {
            if (response.error) {
                lastError = response.error;
                if (callback)
                    callback(false, lastError);
                return;
            }
            refreshPolicies(callback);
        });
    }

    function clearPolicy(appKey, callback) {
        DMSService.sendRequest("cycom.appPolicy.clear", { appKey: String(appKey || "") }, response => {
            if (response.error) {
                lastError = response.error;
                if (callback)
                    callback(false, lastError);
                return;
            }
            refreshPolicies(callback);
        });
    }

    function scopeLabel(scope) {
        switch (String(scope || "")) {
        case "app.read": return I18n.tr("Read app UI");
        case "app.control": return I18n.tr("Control app");
        case "screen.capture": return I18n.tr("Capture screen");
        default: return String(scope || "");
        }
    }
}
