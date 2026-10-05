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
    property string approvalMode: "ask"
    property bool refreshing: false
    property bool responding: false
    property bool modeBusy: false
    property string lastError: ""
    property string lastPresentedId: ""

    readonly property int pendingCount: pendingApprovals.length
    readonly property var currentApproval: pendingCount > 0 ? pendingApprovals[0] : null

    signal pendingChanged
    signal policiesChanged

    Connections {
        target: CyShellService
        function onCapabilitiesReceived() {
            root.refresh();
            root.refreshPolicies();
            root.refreshMode();
        }
        function onAgentEvent(data) {
            root.applyEvent(data);
        }
        function onConnectionStateChanged() {
            if (CyShellService.isConnected) {
                root.refresh();
                root.refreshPolicies();
                root.refreshMode();
                return;
            }
            root.pendingApprovals = [];
            root.appPolicies = [];
            root.approvalMode = "ask";
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
        if (data.state) {
            if (Array.isArray(data.state.appPolicies)) {
                appPolicies = data.state.appPolicies;
                policiesChanged();
            }
            if (data.state.approvalMode !== undefined)
                approvalMode = String(data.state.approvalMode || "ask");
        }
    }

    function refresh() {
        if (refreshing || !CyShellService.isConnected || !(CyShellService.capabilities || []).includes("cycom"))
            return;
        refreshing = true;
        CyShellService.sendRequest("cycom.approvals.list", null, response => {
            refreshing = false;
            if (response.error) {
                lastError = response.error;
                return;
            }
            root.applyPending(Array.isArray(response.result) ? response.result : []);
        });
    }

    function refreshPolicies(callback) {
        if (!CyShellService.isConnected || !(CyShellService.capabilities || []).includes("cycom")) {
            if (callback)
                callback(false, I18n.tr("CyCom runtime unavailable"));
            return;
        }
        CyShellService.sendRequest("cycom.appPolicies.list", null, response => {
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

    function refreshMode(callback) {
        if (!CyShellService.isConnected || !(CyShellService.capabilities || []).includes("cycom")) {
            if (callback)
                callback(false, I18n.tr("CyCom runtime unavailable"));
            return;
        }
        CyShellService.sendRequest("cycom.getRuntimeState", null, response => {
            if (response.error || !response.result) {
                lastError = response.error || I18n.tr("Agent approval mode unavailable");
                if (callback)
                    callback(false, lastError);
                return;
            }
            approvalMode = String(response.result.approvalMode || "ask");
            if (callback)
                callback(true, "");
        });
    }

    function setApprovalMode(mode, callback) {
        if (modeBusy)
            return;
        modeBusy = true;
        CyShellService.sendRequest("cycom.approvalMode.set", {
            mode: String(mode || "ask")
        }, response => {
            modeBusy = false;
            if (response.error || !response.result) {
                lastError = response.error || I18n.tr("Failed to update approval mode");
                if (callback)
                    callback(false, lastError);
                return;
            }
            approvalMode = String(response.result.approvalMode || "ask");
            lastError = "";
            if (callback)
                callback(true, "");
        });
    }

    function respond(decision, callback) {
        const approval = currentApproval;
        if (!approval || responding)
            return;
        responding = true;
        CyShellService.sendRequest("cycom.approval.respond", {
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
        CyShellService.sendRequest("cycom.appPolicy.set", {
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
        CyShellService.sendRequest("cycom.appPolicy.clear", { appKey: String(appKey || "") }, response => {
            if (response.error) {
                lastError = response.error;
                if (callback)
                    callback(false, lastError);
                return;
            }
            refreshPolicies(callback);
        });
    }

    function approvalModeLabel(mode) {
        switch (String(mode || approvalMode)) {
        case "auto": return I18n.tr("Approve for me");
        case "full": return I18n.tr("Full access");
        case "custom": return I18n.tr("Custom");
        default: return I18n.tr("Ask for approval");
        }
    }

    function approvalModeFromLabel(label) {
        if (label === I18n.tr("Approve for me"))
            return "auto";
        if (label === I18n.tr("Full access"))
            return "full";
        if (label === I18n.tr("Custom"))
            return "custom";
        return "ask";
    }

    function policyModeLabel(mode) {
        switch (String(mode || "ask")) {
        case "allow": return I18n.tr("Allow");
        case "deny": return I18n.tr("Deny");
        default: return I18n.tr("Ask");
        }
    }

    function policyModeFromLabel(label) {
        if (label === I18n.tr("Allow"))
            return "allow";
        if (label === I18n.tr("Deny"))
            return "deny";
        return "ask";
    }

    function scopeLabel(scope) {
        switch (String(scope || "")) {
        case "app.read": return I18n.tr("Read app UI");
        case "app.control": return I18n.tr("Control app");
        case "screen.capture": return I18n.tr("View or capture the screen");
        case "files.read": return I18n.tr("Read files");
        case "files.write": return I18n.tr("Change files");
        case "system.read": return I18n.tr("Read system information");
        case "system.control": return I18n.tr("Run or control system operations");
        case "remote.read": return I18n.tr("Read remote targets");
        case "remote.control": return I18n.tr("Control remote targets");
        case "power.control": return I18n.tr("Power or session control");
        case "network.access": return I18n.tr("Access the internet or network");
        case "settings.read": return I18n.tr("Read settings");
        case "settings.write": return I18n.tr("Change settings");
        case "desktop.read": return I18n.tr("Read the desktop");
        case "desktop.control": return I18n.tr("Control CyShell");
        case "window.read": return I18n.tr("Read windows");
        case "window.control": return I18n.tr("Control windows");
        case "workspace.read": return I18n.tr("Read workspaces");
        case "workspace.control": return I18n.tr("Switch workspaces");
        case "device.control": return I18n.tr("Control device hardware");
        default: return String(scope || "");
        }
    }
}
