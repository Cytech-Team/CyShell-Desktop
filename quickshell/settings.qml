import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.CyCommon.Common as DC
import qs.Modals.Settings
import qs.Services

ShellRoot {
    id: root

    // Instantiate the core client before SettingsModal pulls in the much larger
    // Settings/service graph. Otherwise the first CyShellService access can
    // happen from inside a recursive singleton chain and Quickshell leaves a
    // partial object whose socket/isConnected properties are undefined.
    readonly property var coreClient: CyShellService
    readonly property string coreSocketPath: CyShellService.socketPath || ""
    readonly property var settingsModal: settingsLoader.item

    Component.onCompleted: {
        // settings.qml is a separate Quickshell process, so it must wire the
        // shared CyCommon singletons exactly like the main shell entrypoint.
        DC.Style.theme = Theme;
        DC.Style.settings = SettingsData;
        DC.I18n.backend = I18n;
        DC.Paths.backend = Paths;
        DC.Log.backend = Log;
        DC.Host.session = SessionService;
        DC.Host.cache = CacheData;

        // Creating SettingsModal during ShellRoot construction pulls in many
        // service singletons at once. Defer it until the core client above is
        // a complete object, otherwise recursive singleton construction leaves
        // CyShellService partially initialized (socketPath/isConnected undefined).
        settingsLoader.active = true;
    }

    function ensureSettingsModal() {
        if (!settingsLoader.active)
            settingsLoader.active = true;
        return settingsLoader.item;
    }

    function settingsToplevel() {
        const title = I18n.tr("Settings", "settings window title");
        for (const win of ToplevelManager.toplevels.values) {
            if (win && (win.title === "Settings" || win.title === title))
                return win;
        }
        return null;
    }

    function _focusSettingsWindow() {
        const win = settingsToplevel();
        if (!win)
            return false;
        CompositorService.activateToplevel(win);
        return true;
    }

    function showAndFocus(tabName) {
        const modal = ensureSettingsModal();
        if (!modal)
            return "SETTINGS_LOADING";
        SettingsData.reloadFromDisk();
        if (tabName)
            modal.setPageName(String(tabName));
        modal.show();
        focusRetry.restart();
        return "SETTINGS_SHOWN";
    }

    function focusOrToggle(tabName) {
        // Opening Settings should always bring the existing window forward.
        // Explicit toggle() still exists for callers that really want hide/show.
        const modal = ensureSettingsModal();
        if (!modal)
            return "SETTINGS_LOADING";
        if (tabName)
            modal.setPageName(String(tabName));
        if (modal.visible && _focusSettingsWindow())
            return "SETTINGS_FOCUSED";
        return showAndFocus("");
    }

    Timer {
        id: focusRetry
        interval: 40
        repeat: true
        property int attempts: 0
        onTriggered: {
            if (root._focusSettingsWindow() || attempts >= 12) {
                stop();
                attempts = 0;
                return;
            }
            attempts++;
        }
        onRunningChanged: {
            if (running)
                attempts = 0;
        }
    }

    Loader {
        id: settingsLoader
        active: false
        asynchronous: false
        sourceComponent: Component {
            SettingsModal {
                visible: false
            }
        }
    }

    IpcHandler {
        target: "settings"

        function open(): string {
            return root.showAndFocus("");
        }

        function openWithTab(tabName: string): string {
            return root.showAndFocus(tabName);
        }

        function openWithTabIndex(tabIndex: int): string {
            const modal = root.ensureSettingsModal();
            if (!modal)
                return "SETTINGS_LOADING";
            modal.setTabIndex(tabIndex);
            return root.showAndFocus("");
        }

        function close(): string {
            const modal = root.ensureSettingsModal();
            if (modal)
                modal.hide();
            return "SETTINGS_HIDDEN";
        }

        function toggle(): string {
            const modal = root.ensureSettingsModal();
            if (!modal)
                return "SETTINGS_LOADING";
            modal.toggle();
            return modal.visible ? "SETTINGS_SHOWN" : "SETTINGS_HIDDEN";
        }

        function toggleWithTab(tabName: string): string {
            const modal = root.ensureSettingsModal();
            if (!modal)
                return "SETTINGS_LOADING";
            modal.setPageName(tabName);
            modal.toggle();
            return modal.visible ? "SETTINGS_SHOWN" : "SETTINGS_HIDDEN";
        }

        function focusOrToggle(): string {
            return root.focusOrToggle("");
        }

        function focusOrToggleWithTab(tabName: string): string {
            return root.focusOrToggle(tabName);
        }

        function refresh(): string {
            SettingsData.reloadFromDisk();
            return "SETTINGS_REFRESHED";
        }

        function get(key: string): string {
            return JSON.stringify(SettingsData?.[key]);
        }

        function set(key: string, jsonValue: string): string {
            if (!SettingsData.hasSetting(key))
                return "SETTINGS_UNKNOWN_KEY";
            let value;
            try {
                value = JSON.parse(jsonValue);
            } catch (e) {
                value = jsonValue;
            }
            SettingsData.set(key, value);
            return "SETTINGS_SET";
        }

        function sessionGet(key: string): string {
            return JSON.stringify(SessionData?.[key]);
        }

        function sessionDump(): string {
            return SessionData.getCurrentSessionJson();
        }

        function sessionWriteStatus(): string {
            return JSON.stringify({
                pending: SessionData._pendingSessionWrite,
                inFlight: SessionData._sessionWriteInFlight,
                loaded: SessionData._hasLoaded,
                connected: CyShellService.isConnected,
                capabilities: CyShellService.capabilities || []
            });
        }

        function sessionSet(key: string, jsonValue: string): string {
            let value;
            try {
                value = JSON.parse(jsonValue);
            } catch (e) {
                value = jsonValue;
            }
            SessionData.set(key, value);
            return "SESSION_SET";
        }

        function dump(): string {
            return SettingsData.getCurrentSettingsJson();
        }

        function runtimeStatus(): string {
            return JSON.stringify({
                envSocket: Quickshell.env("CYSHELL_SOCKET"),
                serviceConnectedType: typeof CyShellService.isConnected,
                serviceSocketType: typeof CyShellService.socketPath,
                backendConnected: CyShellService.isConnected,
                socketPath: CyShellService.socketPath,
                capabilities: CyShellService.capabilities || [],
                imageCache: DC.Paths.stringify(DC.Paths.imagecache),
                agentAvailable: AgentControlService.available,
                agentError: AgentControlService.lastError,
                integrationAvailable: AgentIntegrationService.available,
                integrationError: AgentIntegrationService.lastError,
                assistantAvailable: AgentAssistantService.available,
                assistantError: AgentAssistantService.lastError,
                assistantEndpoint: AgentAssistantService.endpoint
            });
        }
    }
}
