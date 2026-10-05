import QtQuick
import Quickshell
import qs.Common
import qs.Modals
import qs.Services
import qs.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null
    readonly property int keybindDataVersion: KeybindsService._dataVersion
    readonly property bool keybindsAvailable: KeybindsService.available

    function keysLabel(actionId) {
        void (keybindDataVersion);
        if (!keybindsAvailable)
            return I18n.tr("Manual config");
        const keys = KeybindsService.keysForAction(actionId);
        if (!keys || keys.length === 0)
            return I18n.tr("Not bound");
        return keys.join(", ");
    }

    readonly property string agentOpenAction: "spawn cyshell agent open"
    readonly property string agentReviewAction: "spawn cyshell agent review"
    readonly property string agentStopAction: "spawn cyshell agent stop"

    function openKeybindAction(action) {
        if (!root.parentModal)
            return;
        if (typeof root.parentModal.showKeybindAction === "function")
            root.parentModal.showKeybindAction(action, "");
        else if (typeof root.parentModal.showKeybindsSearch === "function")
            root.parentModal.showKeybindsSearch(action);
        else
            root.parentModal.navigateTo("keybinds");
    }

    function saveIntegration(modeValue, fallbackValue, appValue, tunnelId, tunnelKey, clearCredentials, callback) {
        AgentIntegrationService.configure(
            modeValue,
            fallbackValue,
            appValue,
            tunnelId || "",
            tunnelKey || "",
            clearCredentials === true,
            (success, message) => {
                if (!success) {
                    ToastService.showError(I18n.tr("Agent connection setup failed"), message);
                    if (callback)
                        callback(false);
                    return;
                }
                if (message)
                    ToastService.showWarning(I18n.tr("Agent connection saved"), message);
                else
                    ToastService.showInfo(I18n.tr("Agent connection saved"));
                if (callback)
                    callback(true);
            }
        );
    }

    function agentClientName(clientId) {
        switch (String(clientId || "")) {
        case "codex": return I18n.tr("Codex CLI");
        case "opencode": return I18n.tr("OpenCode");
        case "vscode": return I18n.tr("Visual Studio Code");
        default: return I18n.tr("Agent app");
        }
    }

    function agentClientReason(client) {
        switch (String(client?.reason || "")) {
        case "server_missing": return I18n.tr("CyShell MCP executable is not installed");
        case "config_invalid": return I18n.tr("The client config cannot be read or parsed safely");
        case "config_conflict": return I18n.tr("The reserved CyShell server ID belongs to a different config");
        case "multiple_configs": return I18n.tr("Both OpenCode config files exist, so the active file is ambiguous");
        case "config_override": return I18n.tr("OpenCode uses a custom config path or directory that cannot be confirmed here");
        case "profile_override": return I18n.tr("VS Code uses a portable user profile that cannot be confirmed here");
        case "multiple_user_configs": return I18n.tr("More than one VS Code user config location exists");
        case "profile_selection_unknown": return I18n.tr("A VS Code profile is active, but its user config cannot be confirmed");
        case "config_unavailable": return I18n.tr("The client user config location is unavailable");
        default: return I18n.tr("This client config cannot be updated safely");
        }
    }

    function agentClientSubtitle(client) {
        if (!client?.installed)
            return I18n.tr("Not installed");
        if (!client?.supported || client?.reason === "server_missing")
            return agentClientReason(client);
        return String(client?.configPath || "");
    }

    function agentClientStatus(client) {
        if (!client?.installed)
            return I18n.tr("Not installed");
        if (!client?.supported)
            return I18n.tr("Unavailable");
        if (client?.connected)
            return client?.reason ? I18n.tr("Configured") : I18n.tr("Connected");
        return client?.canConnect ? I18n.tr("Available") : I18n.tr("Unavailable");
    }

    function setAgentClientConnected(client, connected) {
        AgentIntegrationService.setClientConnected(client.id, connected, (success, message) => {
            if (!success) {
                ToastService.showError(I18n.tr("Agent app connection failed"), message);
                return;
            }
            const appName = agentClientName(client.id);
            ToastService.showInfo(connected
                ? I18n.tr("Connected %1", "Connected an Agent app to CyShell MCP").arg(appName)
                : I18n.tr("Disconnected %1", "Disconnected an Agent app from CyShell MCP").arg(appName));
        });
    }

    function receiptTitle(receipt) {
        const action = String(receipt?.action || I18n.tr("Desktop action"));
        const target = String(receipt?.target || "");
        const value = String(receipt?.value || "");
        if (String(receipt?.kind || "") === "setting" && target)
            return value ? `${target} → ${value}` : target;
        return value ? `${action} ${value}` : action;
    }

    function receiptSubtitle(receipt) {
        const expires = Number(receipt?.expiresAt || 0);
        if (expires <= 0)
            return I18n.tr("Undo available in this CyShell session");
        const remaining = Math.max(0, Math.ceil((expires - Date.now()) / 60000));
        const kind = String(receipt?.kind || "");
        const scope = kind === "setting" ? I18n.tr("Setting change") : I18n.tr("Machine action");
        const expiry = remaining > 0 ? I18n.tr("undo for about %1 min", "minutes remaining for Agent action rollback").arg(remaining) : I18n.tr("undo expiring");
        return `${scope} · ${expiry}`;
    }

    function activityStatusLabel(activity) {
        switch (String(activity?.status || "")) {
        case "running": return I18n.tr("Running");
        case "succeeded": return I18n.tr("Completed");
        case "canceled": return I18n.tr("Canceled");
        case "failed": return I18n.tr("Failed");
        default: return I18n.tr("Unknown");
        }
    }

    function activityIcon(activity) {
        switch (String(activity?.status || "")) {
        case "running": return "progress_activity";
        case "succeeded": return "check_circle";
        case "canceled": return "cancel";
        case "failed": return "error";
        default: return "smart_toy";
        }
    }

    function activityColor(activity) {
        switch (String(activity?.status || "")) {
        case "running": return Theme.primary;
        case "succeeded": return Theme.success;
        case "canceled": return Theme.warning;
        case "failed": return Theme.error;
        default: return Theme.surfaceVariantText;
        }
    }

    function activitySubtitle(activity) {
        const parts = [activityStatusLabel(activity)];
        const originName = String(activity?.origin?.name || "");
        const originVersion = String(activity?.origin?.version || "");
        if (originName)
            parts.push(originVersion ? `${originName} ${originVersion}` : originName);
        const duration = Number(activity?.durationMs || 0);
        if (String(activity?.status || "") !== "running" && duration >= 0)
            parts.push(`${duration} ms`);
        const reason = String(activity?.reason || "");
        if (reason)
            parts.push(reason);
        const error = String(activity?.error || "");
        if (error)
            parts.push(error);
        return parts.join(" · ");
    }

    Component.onCompleted: {
        AgentControlService.refresh();
        AgentApprovalService.refreshPolicies();
        AgentApprovalService.refresh();
        AgentIntegrationService.refresh();
        if (KeybindsService.available)
            KeybindsService.loadBinds(false);
    }

    Connections {
        target: AgentControlService
        function onEmergencyStopped() {
            ToastService.showInfo(I18n.tr("Agent control stopped"), I18n.tr("Read-only desktop context remains available. Re-enable control when you are ready."));
        }
    }

    SettingsPage {
        id: page

        SettingsCard {
            width: parent.width
            title: I18n.tr("CyShell Agent")
            iconName: "smart_toy"
            settingKey: "agentRuntimeStatus"
            tags: ["agent", "ai", "cycom", "runtime", "mcp"]

            SettingsRow {
                title: I18n.tr("Embedded runtime")
                subtitle: AgentControlService.available ? I18n.tr("CyCom runs inside the CyShell core") : I18n.tr("CyCom runtime is unavailable")
                iconName: AgentControlService.available ? "memory" : "error"
                iconColor: AgentControlService.available ? Theme.primary : Theme.error
                trailingBadge: AgentControlService.available ? I18n.tr("Connected") : I18n.tr("Offline")
                trailingBadgeColor: AgentControlService.available ? Theme.primary : Theme.error
            }

            SettingsRow {
                visible: AgentControlService.available
                title: I18n.tr("Runtime details")
                subtitle: I18n.tr("%1 tools · %2 active calls · %3", "agent settings status; %1 tool count, %2 active call count, %3 runtime version").arg(AgentControlService.toolCount).arg(AgentControlService.activeCalls).arg(AgentControlService.version || "cyshell-embedded")
                iconName: "hub"
            }

            SettingsRow {
                title: I18n.tr("Assistant")
                subtitle: AgentAssistantService.model ? `${AgentAssistantService.provider} · ${AgentAssistantService.model}` : I18n.tr("Built into CyShell; model is discovered from the configured provider")
                iconName: "chat"

                CyButton {
                    text: I18n.tr("Open Assistant")
                    iconName: "smart_toy"
                    enabled: AgentControlService.available
                    onClicked: PopoutService.showAgentAssistant()
                }
            }

            SettingsToggleRow {
                text: I18n.tr("Enable Agent runtime")
                description: I18n.tr("Allow AI clients to use the embedded CyCom tool runtime")
                checked: AgentControlService.enabled
                enabled: AgentControlService.available && !AgentControlService.busy
                toggling: AgentControlService.busy
                onToggled: value => AgentControlService.setEnabled(value, (success, error) => {
                    if (!success)
                        ToastService.showError(I18n.tr("Failed to update Agent runtime"), error);
                })
            }

            SettingsToggleRow {
                text: I18n.tr("Allow computer control")
                description: I18n.tr("When disabled, read-only semantic context stays available but state-changing tools are blocked")
                checked: AgentControlService.controlEnabled
                enabled: AgentControlService.available && AgentControlService.enabled && !AgentControlService.busy
                toggling: AgentControlService.busy
                onToggled: value => AgentControlService.setControlEnabled(value, (success, error) => {
                    if (!success)
                        ToastService.showError(I18n.tr("Failed to update Agent control"), error);
                })
            }
        }


        SettingsCard {
            width: parent.width
            title: I18n.tr("Agent connections")
            iconName: "lan"
            settingKey: "agentConnections"
            tags: ["agent", "mcp", "tunnel", "chatgpt", "api", "cycom", "fallback"]

            SettingsRow {
                title: I18n.tr("Connection status")
                subtitle: {
                    const parts = [AgentIntegrationService.modeLabel()];
                    if (AgentIntegrationService.mode === "chatgpt-tunnel")
                        parts.push(AgentIntegrationService.tunnelActive ? I18n.tr("Tunnel connected") : I18n.tr("Tunnel stopped"));
                    if (AgentIntegrationService.bridgeActive)
                        parts.push(I18n.tr("API bridge active"));
                    if (AgentIntegrationService.companionActive)
                        parts.push(I18n.tr("CyCom fallback active"));
                    return parts.join(" · ");
                }
                iconName: AgentIntegrationService.lastError ? "error" : "hub"
                iconColor: AgentIntegrationService.lastError ? Theme.error : Theme.primary
                trailingBadge: AgentIntegrationService.available ? I18n.tr("Ready") : I18n.tr("Unavailable")
                trailingBadgeColor: AgentIntegrationService.available ? Theme.primary : Theme.error
            }

            SettingsDropdownRow {
                id: agentConnectionMode
                text: I18n.tr("Connection mode")
                description: I18n.tr("Local keeps CyCom inside CyShell. ChatGPT Tunnel uses Secure MCP Tunnel. Local API exposes loopback HTTP.")
                options: [I18n.tr("Local only"), I18n.tr("ChatGPT Tunnel"), I18n.tr("Local API")]
                currentValue: AgentIntegrationService.modeLabel()
                enabled: AgentIntegrationService.available && !AgentIntegrationService.busy
                onValueChanged: value => root.saveIntegration(
                    AgentIntegrationService.modeFromLabel(value),
                    AgentIntegrationService.externalFallback,
                    AgentIntegrationService.agentAppEnabled,
                    "", "", false
                )
            }

            SettingsToggleRow {
                text: I18n.tr("CyCom companion fallback")
                description: I18n.tr("Prefer embedded CyShell Agent; keep standalone CyCom on loopback as fallback for API and ChatGPT Tunnel")
                checked: AgentIntegrationService.externalFallback
                enabled: AgentIntegrationService.available && !AgentIntegrationService.busy
                toggling: AgentIntegrationService.busy
                onToggled: checked => root.saveIntegration(
                    AgentIntegrationService.mode,
                    checked,
                    AgentIntegrationService.agentAppEnabled,
                    "", "", false
                )
            }

            SettingsRow {
                visible: AgentIntegrationService.externalFallback
                title: I18n.tr("CyCom companion")
                subtitle: AgentIntegrationService.companionInstalled
                    ? (AgentIntegrationService.companionActive
                        ? I18n.tr("Installed and running as fallback")
                        : I18n.tr("Installed; starts automatically when the selected mode needs HTTP fallback"))
                    : I18n.tr("Optional standalone CyCom runtime is not installed")
                iconName: AgentIntegrationService.companionInstalled ? "check_circle" : "download"
                iconColor: AgentIntegrationService.companionInstalled ? Theme.success : Theme.warning
                trailingBadge: AgentIntegrationService.companionInstalled ? I18n.tr("Installed") : I18n.tr("Missing")
                trailingBadgeColor: AgentIntegrationService.companionInstalled ? Theme.success : Theme.warning

                CyButton {
                    visible: !AgentIntegrationService.companionInstalled
                    text: I18n.tr("Install CyCom")
                    iconName: "download"
                    onClicked: AgentIntegrationService.openCompanionInstaller()
                }

                CyButton {
                    visible: AgentIntegrationService.companionInstalled
                    text: I18n.tr("Refresh")
                    iconName: "refresh"
                    onClicked: AgentIntegrationService.refresh()
                }
            }

            SettingsRow {
                visible: AgentIntegrationService.mode === "api" || AgentIntegrationService.mode === "chatgpt-tunnel"
                title: I18n.tr("MCP API")
                subtitle: AgentIntegrationService.apiUrl
                iconName: "api"
                trailingBadge: AgentIntegrationService.bridgeActive ? I18n.tr("Listening") : I18n.tr("Stopped")
                trailingBadgeColor: AgentIntegrationService.bridgeActive ? Theme.success : Theme.surfaceVariantText

                CyButton {
                    text: I18n.tr("Copy URL")
                    iconName: "content_copy"
                    onClicked: {
                        Quickshell.clipboardText = AgentIntegrationService.apiUrl;
                        ToastService.showInfo(I18n.tr("MCP API URL copied"));
                    }
                }
            }

            SettingsRow {
                visible: AgentIntegrationService.mode === "chatgpt-tunnel"
                title: I18n.tr("ChatGPT Tunnel")
                subtitle: AgentIntegrationService.tunnelConfigured
                    ? I18n.tr("Tunnel credentials are saved; leave the fields blank to keep them")
                    : I18n.tr("Add the Secure MCP Tunnel ID and control-plane API key")
                iconName: "cloud_sync"
                trailingBadge: !AgentIntegrationService.tunnelClientInstalled
                    ? I18n.tr("Client missing")
                    : (AgentIntegrationService.tunnelActive ? I18n.tr("Connected") : I18n.tr("Configured"))
                trailingBadgeColor: AgentIntegrationService.tunnelActive
                    ? Theme.success
                    : (AgentIntegrationService.tunnelClientInstalled ? Theme.primary : Theme.warning)
            }

            SettingsTextFieldRow {
                id: tunnelIdField
                visible: AgentIntegrationService.mode === "chatgpt-tunnel"
                text: I18n.tr("Tunnel ID")
                description: AgentIntegrationService.tunnelConfigured
                    ? I18n.tr("Leave blank to keep the saved Tunnel ID")
                    : I18n.tr("Starts with tunnel_")
                placeholderText: AgentIntegrationService.tunnelConfigured ? I18n.tr("Already saved") : "tunnel_..."
                enabled: !AgentIntegrationService.busy
            }

            SettingsRow {
                visible: AgentIntegrationService.mode === "chatgpt-tunnel"
                title: I18n.tr("Control-plane API key")
                subtitle: AgentIntegrationService.tunnelConfigured
                    ? I18n.tr("Stored in a 0600 environment file and never returned to the UI")
                    : I18n.tr("Required by Secure MCP Tunnel")
                iconName: "key"

                CyTextField {
                    id: tunnelKeyField
                    width: Math.min(320, parent.width * 0.48)
                    placeholderText: AgentIntegrationService.tunnelConfigured ? I18n.tr("Key already saved") : I18n.tr("Paste API key")
                    echoMode: TextInput.Password
                    enabled: !AgentIntegrationService.busy
                }
            }

            SettingsRow {
                visible: AgentIntegrationService.mode === "chatgpt-tunnel"
                title: I18n.tr("Tunnel actions")
                subtitle: !AgentIntegrationService.tunnelClientInstalled
                    ? I18n.tr("Install tunnel-client before starting ChatGPT Tunnel")
                    : AgentIntegrationService.lastError
                iconName: AgentIntegrationService.lastError ? "error" : "settings_suggest"
                iconColor: AgentIntegrationService.lastError ? Theme.error : Theme.primary

                Row {
                    spacing: Theme.spacingS

                    CyButton {
                        text: AgentIntegrationService.busy ? I18n.tr("Saving…") : I18n.tr("Save & start")
                        iconName: "save"
                        enabled: !AgentIntegrationService.busy
                            && (AgentIntegrationService.tunnelConfigured
                                || (tunnelIdField.value.trim().length > 0 && tunnelKeyField.text.trim().length > 0))
                        onClicked: root.saveIntegration(
                            "chatgpt-tunnel",
                            AgentIntegrationService.externalFallback,
                            AgentIntegrationService.agentAppEnabled,
                            tunnelIdField.value,
                            tunnelKeyField.text,
                            false,
                            success => {
                                if (!success)
                                    return;
                                tunnelIdField.value = "";
                                tunnelKeyField.text = "";
                            }
                        )
                    }

                    CyButton {
                        visible: AgentIntegrationService.tunnelConfigured
                        text: I18n.tr("Forget credentials")
                        iconName: "key_off"
                        backgroundColor: "transparent"
                        textColor: Theme.error
                        onClicked: root.saveIntegration(
                            AgentIntegrationService.mode,
                            AgentIntegrationService.externalFallback,
                            AgentIntegrationService.agentAppEnabled,
                            "", "", true
                        )
                    }
                }
            }

        }

        SettingsCard {
            width: parent.width
            title: I18n.tr("External Agent apps")
            iconName: "extension"
            settingKey: "externalAgentApps"
            tags: ["agent", "mcp", "codex", "opencode", "vscode", "integration"]

            SettingsRow {
                title: I18n.tr("Installed apps are detected automatically")
                subtitle: I18n.tr("Choose Connect for each app. CyShell changes only that app's user MCP config.")
                iconName: "info"
            }

            Repeater {
                model: AgentIntegrationService.agentClients

                delegate: SettingsRow {
                    required property var modelData

                    title: root.agentClientName(modelData.id)
                    subtitle: root.agentClientSubtitle(modelData)
                    iconName: "smart_toy"
                    iconColor: modelData.connected ? Theme.success : Theme.primary
                    trailingBadge: root.agentClientStatus(modelData)
                    trailingBadgeColor: !modelData.installed
                        ? Theme.surfaceVariantText
                        : (!modelData.supported || modelData.reason ? Theme.warning : (modelData.connected ? Theme.success : Theme.primary))

                    CyButton {
                        visible: modelData.canConnect || modelData.canDisconnect
                        text: modelData.connected ? I18n.tr("Disconnect") : I18n.tr("Connect")
                        iconName: modelData.connected ? "link_off" : "link"
                        enabled: AgentIntegrationService.available && !AgentIntegrationService.busy
                        onClicked: root.setAgentClientConnected(modelData, !modelData.connected)
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            title: I18n.tr("Agent Workspace")
            iconName: "developer_board"
            settingKey: "agentWorkspace"
            tags: ["agent", "workspace", "virtual", "display", "isolated", "remote", "screen"]

            SettingsRow {
                title: AgentControlService.agentWorkspaceActive
                    ? I18n.tr("Agent Workspace is running")
                    : I18n.tr("Agent Workspace is stopped")
                subtitle: AgentControlService.agentWorkspaceActive
                    ? I18n.tr("Isolated Wayland desktop with its own virtual pointer and keyboard. Your physical mouse is not shared.")
                    : I18n.tr("Optional isolated desktop for AI computer control. The normal desktop continues to work when this is off.")
                iconName: AgentControlService.agentWorkspaceActive ? "desktop_windows" : "desktop_access_disabled"
                iconColor: AgentControlService.agentWorkspaceActive ? Theme.success : Theme.surfaceVariantText
                trailingBadge: AgentControlService.agentWorkspaceActive
                    ? (AgentControlService.agentWorkspaceDisplay || I18n.tr("Active"))
                    : I18n.tr("Off")
                trailingBadgeColor: AgentControlService.agentWorkspaceActive ? Theme.success : Theme.surfaceVariantText
            }

            SettingsToggleRow {
                text: I18n.tr("Enable Agent Workspace")
                description: I18n.tr("Start the isolated Agent desktop at login and keep it available for AI control")
                checked: AgentControlService.agentWorkspaceEnabled
                enabled: AgentControlService.available && !AgentControlService.workspaceBusy
                toggling: AgentControlService.workspaceBusy
                onToggled: checked => AgentControlService.setAgentWorkspaceEnabled(checked, (success, error) => {
                    if (!success)
                        ToastService.showError(I18n.tr("Agent Workspace failed"), error);
                })
            }

            SettingsToggleRow {
                text: I18n.tr("Use Agent Workspace automatically")
                description: I18n.tr("When available, Agent screenshots, Any App and generic computer input use the isolated workspace. Turn this off to use the current desktop instead.")
                checked: AgentControlService.useAgentWorkspace
                enabled: AgentControlService.available && !AgentControlService.workspaceBusy
                toggling: AgentControlService.workspaceBusy
                onToggled: checked => AgentControlService.setUseAgentWorkspace(checked, (success, error) => {
                    if (!success)
                        ToastService.showError(I18n.tr("Agent Workspace routing failed"), error);
                })
            }

            SettingsRow {
                visible: AgentControlService.useAgentWorkspace && !AgentControlService.agentWorkspaceActive
                title: I18n.tr("Workspace unavailable")
                subtitle: AgentControlService.agentWorkspaceEnabled
                    ? I18n.tr("The workspace is enabled but not running yet. Automatic tools use the current desktop until it becomes available.")
                    : I18n.tr("Automatic tools use the current desktop while Agent Workspace is disabled.")
                iconName: "info"
                iconColor: Theme.warning
            }

            SettingsTextFieldRow {
                id: workspaceWidthField
                text: I18n.tr("Width")
                description: I18n.tr("Agent Workspace width in pixels (640–7680)")
                value: String(AgentControlService.agentWorkspaceWidth)
                enabled: !AgentControlService.workspaceBusy
            }

            SettingsTextFieldRow {
                id: workspaceHeightField
                text: I18n.tr("Height")
                description: I18n.tr("Agent Workspace height in pixels (480–4320)")
                value: String(AgentControlService.agentWorkspaceHeight)
                enabled: !AgentControlService.workspaceBusy
            }

            SettingsTextFieldRow {
                id: workspaceRefreshField
                text: I18n.tr("Refresh rate")
                description: I18n.tr("Virtual display refresh rate in Hz (24–240)")
                value: String(AgentControlService.agentWorkspaceRefresh)
                enabled: !AgentControlService.workspaceBusy
            }

            SettingsTextFieldRow {
                id: workspaceScaleField
                text: I18n.tr("Scale")
                description: I18n.tr("Logical display scale (0.5–4.0)")
                value: String(AgentControlService.agentWorkspaceScale)
                enabled: !AgentControlService.workspaceBusy
            }

            SettingsRow {
                title: I18n.tr("Workspace display settings")
                subtitle: I18n.tr("The isolated workspace uses one virtual output at position 0,0. Changes apply live when it is running and are remembered for the next start.")
                iconName: "display_settings"

                CyButton {
                    text: AgentControlService.workspaceBusy ? I18n.tr("Applying…") : I18n.tr("Apply")
                    iconName: "check"
                    enabled: {
                        if (AgentControlService.workspaceBusy)
                            return false;
                        const width = Number(workspaceWidthField.value);
                        const height = Number(workspaceHeightField.value);
                        const refresh = Number(workspaceRefreshField.value);
                        const scale = Number(workspaceScaleField.value);
                        return Number.isFinite(width) && width >= 640 && width <= 7680
                            && Number.isFinite(height) && height >= 480 && height <= 4320
                            && Number.isFinite(refresh) && refresh >= 24 && refresh <= 240
                            && Number.isFinite(scale) && scale >= 0.5 && scale <= 4;
                    }
                    onClicked: AgentControlService.configureAgentWorkspace(
                        Number(workspaceWidthField.value),
                        Number(workspaceHeightField.value),
                        Number(workspaceRefreshField.value),
                        Number(workspaceScaleField.value),
                        (success, error) => {
                            if (!success) {
                                ToastService.showError(I18n.tr("Agent Workspace configuration failed"), error);
                                return;
                            }
                            workspaceWidthField.value = String(AgentControlService.agentWorkspaceWidth);
                            workspaceHeightField.value = String(AgentControlService.agentWorkspaceHeight);
                            workspaceRefreshField.value = String(AgentControlService.agentWorkspaceRefresh);
                            workspaceScaleField.value = String(AgentControlService.agentWorkspaceScale);
                            ToastService.showInfo(I18n.tr("Agent Workspace display settings applied"));
                        }
                    )
                }
            }
        }

        SettingsCard {
            width: parent.width
            title: I18n.tr("Keyboard control")
            iconName: "keyboard"
            settingKey: "agentKeyboardControl"
            tags: ["agent", "keyboard", "shortcut", "hotkey", "emergency", "stop"]

            SettingsRow {
                title: I18n.tr("Open Assistant")
                subtitle: root.keybindsAvailable ? I18n.tr("Open or focus the native CyShell Assistant") : I18n.tr("Bind `cyshell agent open` in your compositor config")
                iconName: "smart_toy"
                trailingBadge: root.keysLabel(root.agentOpenAction)
                trailingBadgeColor: Theme.primary
                showChevron: root.keybindsAvailable
                clickable: root.keybindsAvailable
                onClicked: root.openKeybindAction(root.agentOpenAction)
            }

            SettingsRow {
                title: I18n.tr("Review permissions")
                subtitle: root.keybindsAvailable ? I18n.tr("Jump directly to a waiting one-shot Agent approval") : I18n.tr("Bind `cyshell agent review` in your compositor config")
                iconName: "shield_question"
                trailingBadge: root.keysLabel(root.agentReviewAction)
                trailingBadgeColor: AgentApprovalService.pendingCount > 0 ? Theme.warning : Theme.primary
                showChevron: root.keybindsAvailable
                clickable: root.keybindsAvailable
                onClicked: root.openKeybindAction(root.agentReviewAction)
            }

            SettingsRow {
                title: I18n.tr("Emergency stop")
                subtitle: root.keybindsAvailable ? I18n.tr("Revoke computer control and cancel active Agent calls immediately") : I18n.tr("Bind `cyshell agent stop` in your compositor config")
                iconName: "front_hand"
                iconColor: Theme.error
                trailingBadge: root.keysLabel(root.agentStopAction)
                trailingBadgeColor: Theme.error
                showChevron: root.keybindsAvailable
                clickable: root.keybindsAvailable
                onClicked: root.openKeybindAction(root.agentStopAction)
            }
        }

        SettingsCard {
            width: parent.width
            title: I18n.tr("Agent permissions")
            iconName: "admin_panel_settings"
            settingKey: "agentPermissions"
            tags: ["agent", "permission", "scope", "access", "privacy", "control"]

            SettingsRow {
                title: I18n.tr("Permission scopes")
                subtitle: I18n.tr("Each capability is enforced inside the embedded CyCom runtime for the built-in Assistant and external MCP clients")
                iconName: "shield"
                trailingBadge: I18n.tr("%1 scopes", "agent permission scope count").arg(AgentControlService.permissions.length)
                trailingBadgeColor: Theme.primary
            }

            Repeater {
                model: AgentControlService.permissions

                delegate: SettingsToggleRow {
                    required property var modelData

                    text: String(modelData?.label || modelData?.id || "")
                    description: {
                        const category = String(modelData?.category || "");
                        const detail = String(modelData?.description || "");
                        const blocked = modelData?.control === true && !AgentControlService.controlEnabled ? I18n.tr("Currently blocked by the master computer-control switch") : "";
                        return [category, detail, blocked].filter(value => value.length > 0).join(" · ");
                    }
                    checked: modelData?.enabled === true
                    enabled: AgentControlService.available && AgentControlService.enabled && !AgentControlService.busy
                    toggling: AgentControlService.busy
                    onToggled: value => AgentControlService.setPermission(String(modelData.id), value, (success, error) => {
                        if (!success)
                            ToastService.showError(I18n.tr("Failed to update Agent permission"), error);
                    })
                }
            }
        }

        SettingsCard {
            width: parent.width
            title: I18n.tr("Application permissions")
            iconName: "app_registration"
            settingKey: "agentAppPermissions"
            tags: ["agent", "application", "per app", "approval", "session", "always allow", "deny", "full access", "custom"]

            SettingsDropdownRow {
                text: I18n.tr("How should Agent actions be approved?")
                description: I18n.tr("Same model as ChatGPT: ask every time, approve low-risk actions automatically, allow everything, or use your custom rules.")
                options: [
                    I18n.tr("Ask for approval"),
                    I18n.tr("Approve for me"),
                    I18n.tr("Full access"),
                    I18n.tr("Custom")
                ]
                currentValue: AgentApprovalService.approvalModeLabel()
                enabled: !AgentApprovalService.modeBusy
                onValueChanged: value => {
                    const mode = AgentApprovalService.approvalModeFromLabel(value);
                    AgentApprovalService.setApprovalMode(mode, (success, error) => {
                        if (!success)
                            ToastService.showError(I18n.tr("Failed to update approval behavior"), error);
                    });
                }
            }

            SettingsRow {
                visible: AgentApprovalService.approvalMode === "ask"
                title: I18n.tr("Ask for approval")
                subtitle: I18n.tr("The Agent asks before app reading, screen capture, or computer control unless you already remembered an Allow rule.")
                iconName: "pan_tool"
            }

            SettingsRow {
                visible: AgentApprovalService.approvalMode === "auto"
                title: I18n.tr("Approve for me")
                subtitle: I18n.tr("Routine reads, screen capture, settings, window/device actions and network access can proceed automatically. Direct app control plus consequential file, system, remote and power changes still ask first.")
                iconName: "verified_user"
                iconColor: Theme.primary
            }

            SettingsRow {
                visible: AgentApprovalService.approvalMode === "full"
                title: I18n.tr("Full access")
                subtitle: I18n.tr("Unrestricted Agent tool access while the Agent is enabled. Scope toggles, the master control switch, and per-app prompts are bypassed.")
                iconName: "warning"
                iconColor: Theme.warning
                trailingBadge: I18n.tr("Unrestricted")
                trailingBadgeColor: Theme.warning
            }

            SettingsRow {
                visible: AgentApprovalService.approvalMode === "custom"
                title: I18n.tr("Custom")
                subtitle: I18n.tr("Use the capability toggles and remembered per-app Ask / Allow / Deny rules below.")
                iconName: "tune"
                iconColor: Theme.primary
            }

            SettingsRow {
                title: I18n.tr("Pending approvals")
                subtitle: AgentApprovalService.pendingCount > 0
                    ? I18n.tr("The Agent is paused until you review the current capability request")
                    : I18n.tr("No Agent permission requests are waiting")
                iconName: AgentApprovalService.pendingCount > 0 ? "shield_question" : "verified_user"
                iconColor: AgentApprovalService.pendingCount > 0 ? Theme.warning : Theme.primary
                trailingBadge: String(AgentApprovalService.pendingCount)
                trailingBadgeColor: AgentApprovalService.pendingCount > 0 ? Theme.warning : Theme.surfaceVariantText

                CyButton {
                    visible: AgentApprovalService.pendingCount > 0
                    text: I18n.tr("Review")
                    iconName: "visibility"
                    onClicked: PopoutService.showAgentApproval()
                }
            }

            SettingsRow {
                visible: AgentApprovalService.appPolicies.length === 0
                title: I18n.tr("No remembered application rules")
                subtitle: I18n.tr("When you choose Always allow, or set a rule manually, it appears here and can be changed later.")
                iconName: "privacy_tip"
            }

            Repeater {
                model: AgentApprovalService.appPolicies

                delegate: Column {
                    id: appPolicyEditor
                    required property var modelData

                    width: parent.width
                    spacing: Theme.spacingXS
                    readonly property var editableScopes: ["app.read", "app.control", "screen.capture"]
                    readonly property var permissions: modelData?.permissions || {}

                    SettingsRow {
                        width: parent.width
                        title: String(appPolicyEditor.modelData?.appName || appPolicyEditor.modelData?.appKey || I18n.tr("Application"))
                        subtitle: String(appPolicyEditor.modelData?.appKey || "")
                        iconName: "apps"

                        CyButton {
                            text: I18n.tr("Reset")
                            iconName: "restart_alt"
                            onClicked: AgentApprovalService.clearPolicy(String(appPolicyEditor.modelData?.appKey || ""), (success, error) => {
                                if (!success)
                                    ToastService.showError(I18n.tr("Failed to reset application permission"), error);
                            })
                        }
                    }

                    Repeater {
                        model: appPolicyEditor.editableScopes

                        delegate: SettingsDropdownRow {
                            required property string modelData

                            width: appPolicyEditor.width
                            text: AgentApprovalService.scopeLabel(modelData)
                            description: modelData === "app.read"
                                ? I18n.tr("Read semantic UI and accessibility state")
                                : modelData === "app.control"
                                    ? I18n.tr("Click, type, scroll and operate the application")
                                    : I18n.tr("Capture screenshots of the application or desktop")
                            options: [I18n.tr("Ask"), I18n.tr("Allow"), I18n.tr("Deny")]
                            currentValue: AgentApprovalService.policyModeLabel(appPolicyEditor.permissions[modelData] || "ask")
                            enabled: !AgentApprovalService.responding
                            onValueChanged: value => {
                                const mode = AgentApprovalService.policyModeFromLabel(value);
                                AgentApprovalService.setPolicy(
                                    String(appPolicyEditor.modelData?.appKey || ""),
                                    String(appPolicyEditor.modelData?.appName || ""),
                                    String(modelData),
                                    mode,
                                    (success, error) => {
                                        if (!success)
                                            ToastService.showError(I18n.tr("Failed to update application permission"), error);
                                    }
                                );
                            }
                        }
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            title: I18n.tr("Assistant model")
            iconName: "psychology"
            settingKey: "agentProvider"
            tags: ["agent", "assistant", "ai", "model", "provider", "ollama", "openai", "api", "key"]

            SettingsRow {
                title: I18n.tr("Provider")
                subtitle: AgentAssistantService.provider === "anthropic" ? I18n.tr("Native Anthropic Messages API with tool use") : (AgentAssistantService.provider === "gemini" ? I18n.tr("Native Gemini generateContent API with function calling and thought-signature replay") : I18n.tr("OpenAI-compatible endpoint; local Ollama works without an API key"))
                iconName: "cloud_sync"
                trailingBadge: AgentAssistantService.hasApiKey ? I18n.tr("Key in keyring") : I18n.tr("No saved key")
                trailingBadgeColor: AgentAssistantService.hasApiKey ? Theme.primary : Theme.surfaceVariantText
            }

            SettingsDropdownRow {
                id: providerField
                text: I18n.tr("Provider protocol")
                description: I18n.tr("Use native Anthropic or Gemini APIs, or any OpenAI-compatible endpoint")
                currentValue: AgentAssistantService.provider
                options: ["openai-compatible", "anthropic", "gemini"]
                enabled: !AgentAssistantService.configBusy && !AgentAssistantService.busy
                onValueChanged: value => {
                    providerField.currentValue = value;
                    const profile = AgentAssistantService.providerProfile(value);
                    endpointField.value = profile.endpoint;
                    modelField.value = profile.model;
                }
            }

            SettingsTextFieldRow {
                id: endpointField
                text: I18n.tr("API endpoint")
                description: I18n.tr("Example: http://127.0.0.1:11434/v1")
                value: AgentAssistantService.endpoint
                enabled: !AgentAssistantService.configBusy && !AgentAssistantService.busy
            }

            SettingsTextFieldRow {
                id: modelField
                text: I18n.tr("Model")
                description: I18n.tr("Leave empty to auto-select the first model reported by the provider")
                value: AgentAssistantService.model
                enabled: !AgentAssistantService.configBusy && !AgentAssistantService.busy
            }

            SettingsRow {
                title: I18n.tr("API key")
                subtitle: AgentAssistantService.keySource === "environment" ? I18n.tr("Managed by the CyShell process environment") : I18n.tr("Saved securely in the desktop keyring, never in the CyShell config file")
                iconName: "key"

                CyTextField {
                    id: apiKeyField
                    width: Math.min(300, parent.width * 0.46)
                    placeholderText: AgentAssistantService.hasApiKey ? I18n.tr("Key already saved") : I18n.tr("Optional for local providers")
                    echoMode: TextInput.Password
                    enabled: AgentAssistantService.keySource !== "environment" && !AgentAssistantService.configBusy && !AgentAssistantService.busy
                }
            }

            SettingsRow {
                title: I18n.tr("Provider actions")
                subtitle: AgentAssistantService.lastError
                iconName: AgentAssistantService.lastError ? "error" : "settings_suggest"
                iconColor: AgentAssistantService.lastError ? Theme.error : Theme.primary

                Row {
                    spacing: Theme.spacingS

                    CyButton {
                        text: AgentAssistantService.configBusy ? I18n.tr("Saving...") : I18n.tr("Save")
                        iconName: "save"
                        enabled: !AgentAssistantService.configBusy && endpointField.value.trim().length > 0
                        onClicked: AgentAssistantService.configure(providerField.currentValue, endpointField.value, modelField.value, apiKeyField.text, false, (success, error) => {
                            if (!success) {
                                ToastService.showError(I18n.tr("Failed to save Assistant provider"), error);
                                return;
                            }
                            apiKeyField.text = "";
                            ToastService.showInfo(I18n.tr("Assistant provider saved"));
                        })
                    }

                    CyButton {
                        text: I18n.tr("Discover models")
                        iconName: "manage_search"
                        enabled: !AgentAssistantService.configBusy && AgentAssistantService.configured
                        onClicked: AgentAssistantService.discoverModels((success, models, error) => {
                            if (!success) {
                                ToastService.showError(I18n.tr("Model discovery failed"), error);
                                return;
                            }
                            if (models.length === 0) {
                                ToastService.showWarning(I18n.tr("No models found"));
                                return;
                            }
                            if (!modelField.value.trim())
                                modelField.value = String(models[0]);
                            ToastService.showInfo(I18n.tr("Models found"), I18n.tr("%1 available", "number of assistant models available").arg(models.length));
                        })
                    }

                    CyButton {
                        visible: AgentAssistantService.hasApiKey && AgentAssistantService.keySource !== "environment"
                        text: I18n.tr("Clear key")
                        iconName: "key_off"
                        enabled: !AgentAssistantService.configBusy
                        onClicked: AgentAssistantService.configure(providerField.currentValue, endpointField.value, modelField.value, "", true, (success, error) => {
                            if (!success)
                                ToastService.showError(I18n.tr("Failed to clear API key"), error);
                        })
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            title: I18n.tr("Native desktop context")
            iconName: "account_tree"
            settingKey: "agentSemanticDesktop"
            tags: ["agent", "semantic", "windows", "workspaces", "settings", "ui"]

            SettingsRow {
                title: I18n.tr("Semantic UI")
                subtitle: I18n.tr("The Agent can query CyShell surfaces and settings by meaning instead of relying on screenshots")
                iconName: "data_object"
                trailingBadge: I18n.tr("Native")
                trailingBadgeColor: Theme.primary
            }

            SettingsRow {
                title: I18n.tr("Windows")
                subtitle: I18n.tr("Wayland toplevel state and actions are exposed through CyShell")
                iconName: "web_asset"
                trailingBadge: I18n.tr("Semantic")
                trailingBadgeColor: Theme.primary
            }

            SettingsRow {
                title: I18n.tr("Workspaces")
                subtitle: CompositorService.isLabwc ? I18n.tr("Labwc workspaces use ext-workspace-v1 directly") : I18n.tr("Workspace state uses the active compositor backend")
                iconName: "view_carousel"
                trailingBadge: ExtWorkspaceService.available || !CompositorService.isLabwc ? I18n.tr("Available") : I18n.tr("Unavailable")
                trailingBadgeColor: ExtWorkspaceService.available || !CompositorService.isLabwc ? Theme.primary : Theme.error
            }

            SettingsRow {
                title: I18n.tr("Fallback computer use")
                subtitle: I18n.tr("CyCom can still use accessibility, screenshots and input when an app has no semantic API")
                iconName: "touch_app"
            }
        }

        SettingsCard {
            visible: AgentControlService.actionReceipts.length > 0
            width: parent.width
            title: I18n.tr("Undoable Agent actions")
            iconName: "undo"
            settingKey: "agentUndoableActions"
            tags: ["agent", "undo", "rollback", "receipt", "action"]

            SettingsRow {
                title: I18n.tr("Rollback receipts")
                subtitle: I18n.tr("Reversible machine and scalar Settings actions capture their pre-action state. Receipts are session-bound, single-use, and expire automatically.")
                iconName: "receipt_long"
                trailingBadge: String(AgentControlService.actionReceipts.length)
                trailingBadgeColor: Theme.primary
            }

            Repeater {
                model: AgentControlService.actionReceipts.slice(0, 8)

                delegate: SettingsRow {
                    required property var modelData

                    title: root.receiptTitle(modelData)
                    subtitle: root.receiptSubtitle(modelData)
                    iconName: "settings_backup_restore"
                    iconColor: Theme.primary

                    CyButton {
                        text: I18n.tr("Undo")
                        iconName: "undo"
                        enabled: AgentControlService.controlEnabled && !AgentControlService.busy
                        onClicked: AgentControlService.undoReceipt(String(modelData?.id || ""), (success, error) => {
                            if (!success) {
                                ToastService.showError(I18n.tr("Agent rollback failed"), error);
                                return;
                            }
                            ToastService.showInfo(I18n.tr("Agent action rolled back"));
                        })
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            title: I18n.tr("Recent Agent activity")
            iconName: "history"
            settingKey: "agentRecentActivity"
            tags: ["agent", "activity", "history", "audit", "tool", "calls"]

            SettingsRow {
                title: AgentControlService.activeCalls > 0 ? I18n.tr("Agent is working") : I18n.tr("Agent is idle")
                subtitle: AgentControlService.activeCalls > 0 ? I18n.tr("%1 active tool calls", "active Agent tool-call count").arg(AgentControlService.activeCalls) : I18n.tr("Tool activity is streamed live from the CyShell core")
                iconName: AgentControlService.activeCalls > 0 ? "progress_activity" : "check_circle"
                iconColor: AgentControlService.activeCalls > 0 ? Theme.primary : Theme.success
                trailingBadge: I18n.tr("%1 recent", "recent Agent activity count").arg(AgentControlService.recentActivity.length)
                trailingBadgeColor: Theme.primary

                CyButton {
                    visible: AgentControlService.recentActivity.length > 0
                    text: I18n.tr("Clear")
                    iconName: "delete_sweep"
                    onClicked: AgentControlService.clearActivity((success, error) => {
                        if (!success)
                            ToastService.showError(I18n.tr("Failed to clear Agent activity"), error);
                    })
                }
            }

            SettingsRow {
                visible: AgentControlService.recentActivity.length === 0
                title: I18n.tr("No Agent actions yet")
                subtitle: I18n.tr("Semantic and computer-control tool calls will appear here without exposing raw tool arguments")
                iconName: "history_toggle_off"
            }

            Repeater {
                model: AgentControlService.recentActivity.slice(0, 12)

                delegate: SettingsRow {
                    required property var modelData

                    title: String(modelData?.tool || I18n.tr("Agent tool"))
                    subtitle: root.activitySubtitle(modelData)
                    iconName: root.activityIcon(modelData)
                    iconColor: root.activityColor(modelData)
                    trailingBadge: root.activityStatusLabel(modelData)
                    trailingBadgeColor: root.activityColor(modelData)
                }
            }
        }

        SettingsCard {
            width: parent.width
            title: I18n.tr("Emergency control")
            iconName: "emergency"
            settingKey: "agentEmergencyControl"
            tags: ["agent", "stop", "kill", "emergency", "permission"]

            SettingsRow {
                title: I18n.tr("Stop Agent control now")
                subtitle: I18n.tr("Cancels active CyShell Agent calls and blocks new state-changing tool calls until control is enabled again")
                iconName: "front_hand"
                iconColor: Theme.error

                CyButton {
                    text: I18n.tr("Stop control")
                    iconName: "stop_circle"
                    enabled: AgentControlService.available && !AgentControlService.busy
                    backgroundColor: Theme.error
                    textColor: Theme.onError
                    onClicked: AgentControlService.emergencyStop((success, error) => {
                        if (!success)
                            ToastService.showError(I18n.tr("Emergency stop failed"), error);
                    })
                }
            }
        }
    }

}
