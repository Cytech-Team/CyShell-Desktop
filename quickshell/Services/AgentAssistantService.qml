pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("AgentAssistantService")

    property bool available: false
    property bool busy: false
    property string provider: "openai-compatible"
    property string endpoint: ""
    property string model: ""
    property bool configured: false
    property bool hasApiKey: false
    property string keySource: ""
    property var profiles: ({})
    property var availableModels: []
    property bool configBusy: false
    property string lastError: ""
    property var messages: []
    property string pendingMessage: ""
    property var lastToolCalls: []

    signal messageCompleted
    signal historyChanged

    Connections {
        target: DMSService
        function onCapabilitiesReceived() {
            root.refreshState();
        }
        function onConnectionStateChanged() {
            if (DMSService.isConnected) {
                root.refreshState();
                root.loadHistory();
            } else {
                root.available = false;
                root.busy = false;
                root.lastError = I18n.tr("CyShell core disconnected");
            }
        }
    }

    Component.onCompleted: {
        refreshState();
        loadHistory();
    }

    function refreshState(callback) {
        if (!DMSService.isConnected || !(DMSService.capabilities || []).includes("cycom")) {
            available = false;
            if (callback)
                callback(false, I18n.tr("CyCom runtime unavailable"));
            return;
        }
        DMSService.sendRequest("cycom.assistant.getState", null, response => {
            if (response.error || !response.result) {
                available = false;
                lastError = response.error || I18n.tr("Assistant state unavailable");
                if (callback)
                    callback(false, lastError);
                return;
            }
            const state = response.result;
            available = true;
            provider = String(state.provider || "openai-compatible");
            endpoint = String(state.endpoint || "");
            model = String(state.model || "");
            configured = state.configured === true;
            hasApiKey = state.hasApiKey === true;
            keySource = String(state.keySource || "");
            profiles = state.profiles || {};
            lastError = String(state.error || "");
            if (callback)
                callback(true, "");
        });
    }



    function providerDefaultEndpoint(providerValue) {
        switch (String(providerValue || "openai-compatible")) {
        case "anthropic":
            return "https://api.anthropic.com";
        case "gemini":
            return "https://generativelanguage.googleapis.com/v1beta";
        default:
            return "http://127.0.0.1:11434/v1";
        }
    }

    function providerProfile(providerValue) {
        const id = String(providerValue || "openai-compatible");
        const profile = profiles?.[id];
        if (profile)
            return { endpoint: String(profile.endpoint || providerDefaultEndpoint(id)), model: String(profile.model || "") };
        return { endpoint: providerDefaultEndpoint(id), model: "" };
    }

    function configure(providerValue, endpointValue, modelValue, apiKeyValue, clearKey, callback) {
        if (configBusy)
            return;
        configBusy = true;
        DMSService.sendRequest("cycom.assistant.configure", {
            provider: String(providerValue || provider || "openai-compatible"),
            endpoint: String(endpointValue || "").trim(),
            model: String(modelValue || "").trim(),
            apiKey: String(apiKeyValue || ""),
            clearKey: clearKey === true
        }, response => {
            configBusy = false;
            if (response.error || !response.result) {
                lastError = response.error || I18n.tr("Failed to save Assistant provider");
                if (callback)
                    callback(false, lastError);
                return;
            }
            const state = response.result;
            available = true;
            provider = String(state.provider || "openai-compatible");
            endpoint = String(state.endpoint || "");
            model = String(state.model || "");
            configured = state.configured === true;
            hasApiKey = state.hasApiKey === true;
            keySource = String(state.keySource || "");
            profiles = state.profiles || {};
            lastError = String(state.error || "");
            if (callback)
                callback(true, "");
        }, 130000);
    }

    function discoverModels(callback) {
        if (configBusy)
            return;
        configBusy = true;
        DMSService.sendRequest("cycom.assistant.models", null, response => {
            configBusy = false;
            if (response.error) {
                lastError = response.error;
                if (callback)
                    callback(false, [], lastError);
                return;
            }
            availableModels = Array.isArray(response.result) ? response.result : [];
            lastError = "";
            if (callback)
                callback(true, availableModels, "");
        }, 45000);
    }

    function loadHistory(callback) {
        if (!DMSService.isConnected || !(DMSService.capabilities || []).includes("cycom")) {
            if (callback)
                callback(false, I18n.tr("CyCom runtime unavailable"));
            return;
        }
        DMSService.sendRequest("cycom.chat.history", null, response => {
            if (response.error) {
                lastError = response.error;
                if (callback)
                    callback(false, lastError);
                return;
            }
            messages = Array.isArray(response.result) ? response.result : [];
            historyChanged();
            if (callback)
                callback(true, "");
        });
    }

    function send(message) {
        const text = String(message || "").trim();
        if (!text || busy)
            return false;
        if (!AgentControlService.enabled) {
            lastError = I18n.tr("Agent runtime is disabled");
            return false;
        }

        busy = true;
        pendingMessage = text;
        lastError = "";
        const optimistic = messages.slice();
        optimistic.push({ role: "user", content: text });
        messages = optimistic;
        historyChanged();

        DMSService.sendRequest("cycom.chat", { message: text }, response => {
            busy = false;
            pendingMessage = "";
            if (response.error || !response.result) {
                lastError = response.error || I18n.tr("Assistant request failed");
                const failed = messages.slice();
                failed.push({ role: "error", content: lastError });
                messages = failed;
                historyChanged();
                return;
            }
            const result = response.result;
            const updated = messages.slice();
            updated.push({ role: "assistant", content: String(result.message || "") });
            messages = updated;
            model = String(result.model || model);
            lastToolCalls = Array.isArray(result.toolCalls) ? result.toolCalls : [];
            lastError = "";
            historyChanged();
            messageCompleted();
        }, 180000);
        return true;
    }

    function clear() {
        if (busy)
            return;
        DMSService.sendRequest("cycom.chat.clear", null, response => {
            if (response.error) {
                lastError = response.error;
                return;
            }
            messages = [];
            lastToolCalls = [];
            lastError = "";
            historyChanged();
        });
    }
}
