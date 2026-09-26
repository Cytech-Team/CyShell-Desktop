import QtQuick
import qs.Common
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

    function openKeybindsSearch(query) {
        if (!root.parentModal)
            return;
        if (typeof root.parentModal.showKeybindsSearch === "function")
            root.parentModal.showKeybindsSearch(query);
        else
            root.parentModal.navigateTo("keybinds");
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

                DankButton {
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
            title: I18n.tr("Keyboard control")
            iconName: "keyboard"
            settingKey: "agentKeyboardControl"
            tags: ["agent", "keyboard", "shortcut", "hotkey", "emergency", "stop"]

            SettingsRow {
                title: I18n.tr("Open Assistant")
                subtitle: root.keybindsAvailable ? I18n.tr("Open or focus the native CyShell Assistant") : I18n.tr("Bind `dms agent open` in your compositor config")
                iconName: "smart_toy"
                trailingBadge: root.keysLabel("spawn dms agent open")
                trailingBadgeColor: Theme.primary
                showChevron: root.keybindsAvailable
                clickable: root.keybindsAvailable
                onClicked: root.openKeybindsSearch("dms agent open")
            }

            SettingsRow {
                title: I18n.tr("Review permissions")
                subtitle: root.keybindsAvailable ? I18n.tr("Jump directly to a waiting one-shot Agent approval") : I18n.tr("Bind `dms agent review` in your compositor config")
                iconName: "shield_question"
                trailingBadge: root.keysLabel("spawn dms agent review")
                trailingBadgeColor: AgentApprovalService.pendingCount > 0 ? Theme.warning : Theme.primary
                showChevron: root.keybindsAvailable
                clickable: root.keybindsAvailable
                onClicked: root.openKeybindsSearch("dms agent review")
            }

            SettingsRow {
                title: I18n.tr("Emergency stop")
                subtitle: root.keybindsAvailable ? I18n.tr("Revoke computer control and cancel active Agent calls immediately") : I18n.tr("Bind `dms agent stop` in your compositor config")
                iconName: "front_hand"
                iconColor: Theme.error
                trailingBadge: root.keysLabel("spawn dms agent stop")
                trailingBadgeColor: Theme.error
                showChevron: root.keybindsAvailable
                clickable: root.keybindsAvailable
                onClicked: root.openKeybindsSearch("dms agent stop")
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
            tags: ["agent", "application", "per app", "approval", "allow once", "always allow", "deny"]

            SettingsRow {
                title: I18n.tr("Pending approvals")
                subtitle: AgentApprovalService.pendingCount > 0 ? I18n.tr("The Agent is paused until you review the request") : I18n.tr("No Agent permission requests are waiting")
                iconName: AgentApprovalService.pendingCount > 0 ? "shield_question" : "verified_user"
                iconColor: AgentApprovalService.pendingCount > 0 ? Theme.warning : Theme.primary
                trailingBadge: String(AgentApprovalService.pendingCount)
                trailingBadgeColor: AgentApprovalService.pendingCount > 0 ? Theme.warning : Theme.surfaceVariantText

                DankButton {
                    visible: AgentApprovalService.pendingCount > 0
                    text: I18n.tr("Review")
                    iconName: "visibility"
                    onClicked: PopoutService.showAgentApproval()
                }
            }

            SettingsRow {
                visible: AgentApprovalService.appPolicies.length === 0
                title: I18n.tr("Ask by default")
                subtitle: I18n.tr("Third-party app reading, control, and screenshots ask for consent until you choose Always allow or Always deny")
                iconName: "privacy_tip"
            }

            Repeater {
                model: AgentApprovalService.appPolicies

                delegate: SettingsRow {
                    required property var modelData

                    title: String(modelData?.appName || modelData?.appKey || I18n.tr("Application"))
                    subtitle: {
                        const permissions = modelData?.permissions || {};
                        const parts = [];
                        for (const scope of Object.keys(permissions)) {
                            const mode = String(permissions[scope] || "ask");
                            const modeLabel = mode === "allow" ? I18n.tr("Always allow") : I18n.tr("Always deny");
                            parts.push(`${AgentApprovalService.scopeLabel(scope)}: ${modeLabel}`);
                        }
                        return parts.length > 0 ? parts.join(" · ") : I18n.tr("Ask every time");
                    }
                    iconName: "apps"

                    DankButton {
                        text: I18n.tr("Reset")
                        iconName: "restart_alt"
                        onClicked: AgentApprovalService.clearPolicy(String(modelData.appKey || ""), (success, error) => {
                            if (!success)
                                ToastService.showError(I18n.tr("Failed to reset application permission"), error);
                        })
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

                DankTextField {
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

                    DankButton {
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

                    DankButton {
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

                    DankButton {
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

                    DankButton {
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

                DankButton {
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

                DankButton {
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
