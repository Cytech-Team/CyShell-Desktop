pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

Singleton {
    id: root

    readonly property var log: Log.scoped("AgentIntegrationService")

    property bool available: false
    property bool busy: false
    property string mode: "local"
    property bool externalFallback: true
    property bool agentAppEnabled: false
    property var agentClients: []
    property bool companionInstalled: false
    property bool tunnelClientInstalled: false
    property bool tunnelConfigured: false
    property bool bridgeInstalled: false
    property bool bridgeActive: false
    property bool companionActive: false
    property bool tunnelActive: false
    property string apiUrl: "http://127.0.0.1:7333/mcp"
    property string agentAppConfigPath: ""
    property string integrationConfigPath: ""
    property string tunnelCredentialsPath: ""
    property string lastError: ""

    signal stateChanged

    Connections {
        target: CyShellService

        function onCapabilitiesReceived() {
            root.refresh();
        }

        function onConnectionStateChanged() {
            if (CyShellService.isConnected)
                root.refresh();
            else {
                root.available = false;
                root.agentClients = [];
            }
        }
    }

    Component.onCompleted: refresh()

    function applyState(state) {
        available = true;
        mode = String(state?.mode || "local");
        externalFallback = state?.externalFallback !== false;
        agentAppEnabled = state?.agentAppEnabled === true;
        agentClients = Array.isArray(state?.agentClients) ? state.agentClients : [];
        companionInstalled = state?.companionInstalled === true;
        tunnelClientInstalled = state?.tunnelClientInstalled === true;
        tunnelConfigured = state?.tunnelConfigured === true;
        bridgeInstalled = state?.bridgeInstalled === true;
        bridgeActive = state?.bridgeActive === true;
        companionActive = state?.companionActive === true;
        tunnelActive = state?.tunnelActive === true;
        apiUrl = String(state?.apiUrl || "http://127.0.0.1:7333/mcp");
        agentAppConfigPath = String(state?.agentAppConfigPath || "");
        integrationConfigPath = String(state?.integrationConfigPath || "");
        tunnelCredentialsPath = String(state?.tunnelCredentialsPath || "");
        lastError = String(state?.lastError || "");
        stateChanged();
    }

    function refresh(callback) {
        if (!CyShellService.isConnected || !(CyShellService.capabilities || []).includes("cycom")) {
            available = false;
            if (callback)
                callback(false, I18n.tr("CyCom runtime unavailable"));
            return;
        }

        CyShellService.sendRequest("cycom.integration.get", null, response => {
            if (response.error || !response.result) {
                available = false;
                lastError = response.error || I18n.tr("Agent integration state unavailable");
                if (callback)
                    callback(false, lastError);
                return;
            }
            applyState(response.result);
            if (callback)
                callback(true, "");
        });
    }

    function configure(modeValue, fallbackValue, agentAppValue, tunnelId, tunnelApiKey, clearTunnelCredentials, callback) {
        if (busy)
            return;

        busy = true;
        CyShellService.sendRequest("cycom.integration.configure", {
            mode: String(modeValue || "local"),
            externalFallback: fallbackValue === true,
            agentAppEnabled: agentAppValue === true,
            tunnelId: String(tunnelId || ""),
            tunnelApiKey: String(tunnelApiKey || ""),
            clearTunnelCredentials: clearTunnelCredentials === true
        }, response => {
            busy = false;
            if (response.error || !response.result) {
                lastError = response.error || I18n.tr("Failed to configure Agent connection");
                if (callback)
                    callback(false, lastError);
                return;
            }
            applyState(response.result);
            if (callback)
                callback(true, lastError);
        }, 45000);
    }

    function setClientConnected(clientId, connected, callback) {
        if (busy)
            return;

        busy = true;
        CyShellService.sendRequest("cycom.integration.client.set", {
            clientId: String(clientId || ""),
            connected: connected === true
        }, response => {
            busy = false;
            if (response.error || !response.result) {
                lastError = response.error || I18n.tr("Failed to update Agent app connection");
                if (callback)
                    callback(false, lastError);
                return;
            }
            applyState(response.result);
            if (callback)
                callback(true, lastError);
        }, 45000);
    }

    function modeLabel(value) {
        switch (String(value || mode)) {
        case "chatgpt-tunnel":
            return I18n.tr("ChatGPT Tunnel");
        case "api":
            return I18n.tr("Local API");
        default:
            return I18n.tr("Local only");
        }
    }

    function modeFromLabel(label) {
        if (label === I18n.tr("ChatGPT Tunnel"))
            return "chatgpt-tunnel";
        if (label === I18n.tr("Local API"))
            return "api";
        return "local";
    }

    function openCompanionInstaller() {
        const terminal = SessionData.resolveTerminal()
            || SessionData.installedTerminals?.[0]
            || "qterminal";
        const command = "curl -fsSL https://cdn.cytechteam.site/install/cycomagent | sh; printf '\\nCyCom install finished. Press Enter to close.\\n'; read";
        if (terminal === "qterminal") {
            Quickshell.execDetached(["qterminal", "-e", "bash", "-lc", command]);
            return;
        }
        Quickshell.execDetached([terminal, "-e", "bash", "-lc", command]);
    }
}
