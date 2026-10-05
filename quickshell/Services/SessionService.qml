pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.I3
import Quickshell.Wayland
import qs.Common
import qs.Services
import "../Common/SessionLaunch.js" as SessionLaunch

Singleton {
    id: root
    readonly property var log: Log.scoped("SessionService")

    // Qt.platform.os is "unix" on the BSDs (qtdeclarative qqmlplatform.cpp)
    readonly property bool isBSD: Qt.platform.os === "unix"
    property bool hasUwsm: false
    property bool isElogind: false
    property bool loginctlCommandAvailable: false
    property bool systemctlCommandAvailable: false
    property bool systemdRunCommandAvailable: false
    property bool userManagerAvailable: false
    property bool hibernateSupported: false
    readonly property bool softRebootSupported: systemctlCommandAvailable
    property bool inhibitorAvailable: true
    property bool idleInhibited: false
    property string inhibitReason: "Keep system awake"
    property string nvidiaCommand: ""
    property var _recentDesktopLaunches: ({})
    property var _pendingDesktopActivations: []

    function allowDesktopLaunch(key) {
        const normalized = String(key || "").trim();
        if (!normalized)
            return true;
        const now = Date.now();
        const previous = Number(_recentDesktopLaunches[normalized] || 0);
        if (now - previous < 350)
            return false;
        _recentDesktopLaunches[normalized] = now;
        return true;
    }

    function normalizedDesktopLaunchIdentifier(value) {
        return String(value || "").trim().replace(/\.desktop$/i, "").toLowerCase();
    }

    function desktopLaunchMatches(request, toplevel) {
        const appId = normalizedDesktopLaunchIdentifier(toplevel?.appId);
        if (!appId)
            return false;
        return request.identifiers.some(identifier => appId === identifier || appId.endsWith("." + identifier) || identifier.endsWith("." + appId));
    }

    function trackDesktopLaunch(desktopEntry) {
        const identifiers = [desktopEntry?.startupClass, desktopEntry?.id]
            .map(value => normalizedDesktopLaunchIdentifier(value))
            .filter(value => value.length > 0);
        if (identifiers.length === 0)
            return;

        const windows = Array.from(ToplevelManager.toplevels.values || []);
        _pendingDesktopActivations = _pendingDesktopActivations.concat([{
            identifiers: Array.from(new Set(identifiers)),
            existing: windows,
            previousActive: ToplevelManager.activeToplevel,
            deadline: Date.now() + 3000
        }]);
        desktopLaunchActivationTimer.start();
    }

    function resolvePendingDesktopActivations() {
        if (_pendingDesktopActivations.length === 0) {
            desktopLaunchActivationTimer.stop();
            return;
        }

        const windows = Array.from(ToplevelManager.toplevels.values || []);
        const active = ToplevelManager.activeToplevel;
        const now = Date.now();
        const pending = [];

        for (const request of _pendingDesktopActivations) {
            const newWindow = windows.find(window => !request.existing.includes(window) && desktopLaunchMatches(request, window));
            const activeMatches = active && desktopLaunchMatches(request, active);
            const target = newWindow || (activeMatches && !request.existing.includes(active) ? active : null);
            if (target) {
                CompositorService.activateToplevel(target);
                continue;
            }

            if (activeMatches && active !== request.previousActive)
                continue;

            if (active && active !== request.previousActive)
                continue;

            if (now >= request.deadline) {
                const existingWindow = windows.find(window => request.existing.includes(window) && desktopLaunchMatches(request, window));
                if (existingWindow)
                    CompositorService.activateToplevel(existingWindow);
                continue;
            }

            pending.push(request);
        }

        _pendingDesktopActivations = pending;
        if (pending.length === 0)
            desktopLaunchActivationTimer.stop();
    }

    property bool loginctlAvailable: false
    property string sessionId: ""
    property string sessionPath: ""
    property bool locked: false
    property bool active: false
    property bool idleHint: false
    property bool lockedHint: false
    property bool preparingForSleep: false
    property string sessionType: ""
    property string userName: ""
    property string seat: ""
    property string display: ""

    signal sessionLocked
    signal sessionUnlocked
    signal sessionResumed
    signal loginctlStateChanged

    Timer {
        id: desktopLaunchActivationTimer
        interval: 100
        repeat: true
        onTriggered: root.resolvePendingDesktopActivations()
    }

    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() {
            if (root._pendingDesktopActivations.length > 0)
                root.resolvePendingDesktopActivations();
        }
    }

    property bool stateInitialized: false
    property string prepareForSleepSubscriptionId: ""
    property bool prepareForSleepSubscriptionPending: false
    property double lastResumeSignalTimestamp: 0

    readonly property string socketPath: Quickshell.env("CYSHELL_SOCKET")

    Timer {
        id: sessionInitTimer
        interval: 200
        running: true
        repeat: false
        onTriggered: {
            detectUwsmProcess.running = true;
            detectElogindProcess.running = true;
            detectLoginctlProcess.running = true;
            detectSystemctlProcess.running = true;
            detectSystemdRunProcess.running = true;
            detectHibernateProcess.running = true;
            detectPrimeRunProcess.running = true;
            if (!SettingsData.loginctlLockIntegration) {
                log.debug("loginctl lock integration disabled by user");
                return;
            }
            if (socketPath && socketPath.length > 0) {
                checkDMSCapabilities();
            } else {
                log.debug("CYSHELL_SOCKET not set");
            }
        }
    }

    Process {
        id: detectUwsmProcess
        running: false
        command: ["sh", "-c", "command -v uwsm > /dev/null 2>&1 && systemctl --user is-active --quiet 'wayland-wm@*.service' 2> /dev/null"]

        onExited: function (exitCode) {
            hasUwsm = (exitCode === 0);
        }
    }

    Process {
        id: detectElogindProcess
        running: false
        command: ["sh", "-c", "ps -eo comm= | grep -E '^(elogind|elogind-daemon)$'"]

        onExited: function (exitCode) {
            log.debug("Elogind detection exited with code", exitCode);
            isElogind = (exitCode === 0);
        }
    }

    Process {
        id: detectLoginctlProcess
        running: false
        command: ["sh", "-c", "command -v loginctl"]

        onExited: function (exitCode) {
            loginctlCommandAvailable = (exitCode === 0);
        }
    }

    Process {
        id: detectSystemctlProcess
        running: false
        command: ["sh", "-c", "command -v systemctl > /dev/null || exit 1; systemctl --user show-environment > /dev/null 2>&1 || exit 2"]

        onExited: function (exitCode) {
            systemctlCommandAvailable = (exitCode === 0 || exitCode === 2);
            userManagerAvailable = (exitCode === 0);
        }
    }

    Process {
        id: detectSystemdRunProcess
        running: false
        command: ["sh", "-c", "command -v systemd-run > /dev/null 2>&1 && systemctl --user show-environment > /dev/null 2>&1"]

        onExited: function (exitCode) {
            systemdRunCommandAvailable = (exitCode === 0);
        }
    }

    Process {
        id: detectHibernateProcess
        running: false
        command: ["grep", "-q", "disk", "/sys/power/state"]

        onExited: function (exitCode) {
            hibernateSupported = (exitCode === 0);
        }
    }

    Process {
        id: hibernateProcess
        running: false

        property string errorOutput: ""

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => hibernateProcess.errorOutput += data.trim()
        }

        onExited: function (exitCode) {
            if (exitCode === 0) {
                errorOutput = "";
                return;
            }
            ToastService.showError(I18n.tr("Hibernate failed"), errorOutput);
            errorOutput = "";
        }
    }

    Process {
        id: detectPrimeRunProcess
        running: false
        command: ["sh", "-c", "command -v prime-run"]

        onExited: function (exitCode) {
            if (exitCode === 0) {
                nvidiaCommand = "prime-run";
            } else {
                detectNvidiaOffloadProcess.running = true;
            }
        }
    }

    Process {
        id: detectNvidiaOffloadProcess
        running: false
        command: ["sh", "-c", "command -v nvidia-offload"]

        onExited: function (exitCode) {
            if (exitCode === 0) {
                nvidiaCommand = "nvidia-offload";
            }
        }
    }

    Process {
        id: uwsmLogout
        property bool notRunning: false
        command: ["uwsm", "stop"]
        running: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.trim().toLowerCase().includes("not running"))
                    uwsmLogout.notRunning = true;
            }
        }

        onExited: function (exitCode) {
            if (exitCode === 0 && !notRunning) {
                return;
            }
            _logout();
        }
    }

    function escapeShellArg(arg) {
        return "'" + arg.replace(/'/g, "'\\''") + "'";
    }

    function needsShellExecution(prefix) {
        if (!prefix || prefix.length === 0)
            return false;
        return /[;&|<>()$`\\"']/.test(prefix);
    }

    function parseEnvVars(envVarsStr) {
        if (!envVarsStr || envVarsStr.trim().length === 0)
            return {};
        const envObj = {};
        const pairs = envVarsStr.trim().split(/\s+/);
        for (const pair of pairs) {
            const eqIndex = pair.indexOf("=");
            if (eqIndex > 0) {
                const key = pair.substring(0, eqIndex);
                const value = pair.substring(eqIndex + 1);
                envObj[key] = value;
            }
        }
        return envObj;
    }

    function splitShellArgs(str) {
        const args = [];
        let current = "";
        let hasToken = false;
        let quote = "";
        let escaped = false;
        for (const ch of str) {
            if (escaped) {
                current += ch;
                escaped = false;
                continue;
            }
            switch (quote) {
            case "'":
                if (ch === "'") {
                    quote = "";
                    continue;
                }
                current += ch;
                continue;
            case "\"":
                switch (ch) {
                case "\"":
                    quote = "";
                    continue;
                case "\\":
                    escaped = true;
                    continue;
                }
                current += ch;
                continue;
            }
            switch (ch) {
            case "\\":
                escaped = true;
                continue;
            case "'":
            case "\"":
                quote = ch;
                hasToken = true;
                continue;
            case " ":
            case "\t":
            case "\n":
                if (!hasToken && current.length === 0)
                    continue;
                args.push(current);
                current = "";
                hasToken = false;
                continue;
            }
            current += ch;
        }
        if (current.length > 0 || hasToken)
            args.push(current);
        return args;
    }

    // Restore pre-wrap Qt paths (Nix) so launched apps use their own.
    function restoreWrapperEnv(env) {
        const restore = (target, snapshot) => {
            const orig = Quickshell.env(snapshot);
            if (orig === null)
                return;
            env[target] = orig.length > 0 ? orig : null;
        };
        restore("NIXPKGS_QT6_QML_IMPORT_PATH", Quickshell.env("CYSHELL_ORIG_NIXPKGS_QT6_QML_IMPORT_PATH") !== "" ? "CYSHELL_ORIG_NIXPKGS_QT6_QML_IMPORT_PATH" : "DMS_ORIG_NIXPKGS_QT6_QML_IMPORT_PATH");
        restore("QT_PLUGIN_PATH", Quickshell.env("CYSHELL_ORIG_QT_PLUGIN_PATH") !== "" ? "CYSHELL_ORIG_QT_PLUGIN_PATH" : "DMS_ORIG_QT_PLUGIN_PATH");
        return env;
    }

    function desktopAppEnvironment(override, includeCustomEnvVars) {
        const cursorEnv = typeof SettingsData.getCursorEnvironment === "function" ? SettingsData.getCursorEnvironment() : {};
        const customEnv = includeCustomEnvVars && override?.envVars ? parseEnvVars(override.envVars) : {};
        const env = Object.assign({}, cursorEnv, customEnv);
        const locale = String(override?.locale || "").trim();
        if (/^(?:[A-Za-z]{2,3}(?:[_-][A-Za-z0-9]{2,8})*|C|POSIX)(?:\.[A-Za-z0-9_-]+)?(?:@[A-Za-z0-9_-]+)?$/.test(locale)) {
            env.LANG = locale;
            env.LANGUAGE = locale.split(/[.@]/)[0];
            env.LC_MESSAGES = locale;
        }
        return restoreWrapperEnv(env);
    }

    // GUI apps must not remain in cyshell.service's cgroup. A shell restart
    // stops that whole control group, which would otherwise terminate apps that
    // were launched with Quickshell.execDetached(). Move every desktop launch
    // into its own transient user scope under app.slice first.
    function appScopeCommand(command) {
        return SessionLaunch.appScopeCommand(command, !isBSD && systemdRunCommandAvailable && userManagerAvailable);
    }

    function launchDetachedApp(command, workingDirectory, environment) {
        const argv = appScopeCommand(command);
        if (argv.length === 0)
            return;
        const options = { command: argv };
        if (workingDirectory)
            options.workingDirectory = workingDirectory;
        if (environment)
            options.environment = environment;
        Quickshell.execDetached(options);
    }

    function openUrl(url, workingDirectory) {
        const target = String(url || "").trim();
        if (!target)
            return;
        launchDetachedApp(["xdg-open", target], workingDirectory || Quickshell.env("HOME"), {});
    }

    function launchDesktopEntry(desktopEntry, useNvidia) {
        if (!desktopEntry || !desktopEntry.command)
            return;
        CompositorService.closeNiriOverviewOnWindowFocus();
        let cmd = desktopEntry.command;

        const appId = desktopEntry.id || desktopEntry.execString || desktopEntry.exec || "";
        if (!allowDesktopLaunch("app:" + appId))
            return;
        trackDesktopLaunch(desktopEntry);
        const override = SessionData.getAppOverride(appId);

        const dgpu = useNvidia || (override?.launchOnDgpu && nvidiaCommand);
        if (dgpu && nvidiaCommand)
            cmd = [nvidiaCommand].concat(cmd);

        if (override?.extraFlags) {
            cmd = cmd.concat(splitShellArgs(override.extraFlags));
        }

        const userPrefix = SettingsData.launchPrefix?.trim() || "";
        const envPrefix = (Quickshell.env("CYSHELL_DEFAULT_LAUNCH_PREFIX") || "").trim();
        const defaultPrefix = envPrefix.startsWith("systemd-run ") ? "" : envPrefix;
        const prefix = userPrefix.length > 0 ? userPrefix : defaultPrefix;
        const workDir = desktopEntry.workingDirectory || Quickshell.env("HOME");
        const finalEnv = desktopAppEnvironment(override, true);

        if (desktopEntry.runInTerminal) {
            const terminal = SessionData.resolveTerminal() || "xterm";
            const escapedCmd = cmd.map(arg => escapeShellArg(arg)).join(" ");
            const shellCmd = prefix.length > 0 ? `${prefix} ${escapedCmd}` : escapedCmd;
            launchDetachedApp([terminal, "-e", "sh", "-c", shellCmd], workDir, finalEnv);
            return;
        }

        if (prefix.length > 0 && needsShellExecution(prefix)) {
            const escapedCmd = cmd.map(arg => escapeShellArg(arg)).join(" ");
            launchDetachedApp(["sh", "-c", `${prefix} ${escapedCmd}`], workDir, finalEnv);
            return;
        }

        if (prefix.length > 0)
            cmd = prefix.split(" ").concat(cmd);

        launchDetachedApp(cmd, workDir, finalEnv);
    }

    function launchDesktopAction(desktopEntry, action, useNvidia) {
        if (!desktopEntry || !action || !action.command)
            return;
        CompositorService.closeNiriOverviewOnWindowFocus();
        let cmd = action.command;

        const appId = desktopEntry.id || desktopEntry.execString || desktopEntry.exec || "";
        if (!allowDesktopLaunch("app:" + appId))
            return;
        trackDesktopLaunch(desktopEntry);
        const override = SessionData.getAppOverride(appId);
        const dgpu = useNvidia || (override?.launchOnDgpu && nvidiaCommand);
        if (dgpu && nvidiaCommand)
            cmd = [nvidiaCommand].concat(cmd);

        const userPrefix = SettingsData.launchPrefix?.trim() || "";
        const envPrefix = (Quickshell.env("CYSHELL_DEFAULT_LAUNCH_PREFIX") || "").trim();
        const defaultPrefix = envPrefix.startsWith("systemd-run ") ? "" : envPrefix;
        const prefix = userPrefix.length > 0 ? userPrefix : defaultPrefix;
        const workDir = desktopEntry.workingDirectory || Quickshell.env("HOME");
        const finalEnv = desktopAppEnvironment(override, false);

        if (prefix.length > 0 && needsShellExecution(prefix)) {
            const escapedCmd = cmd.map(arg => escapeShellArg(arg)).join(" ");
            launchDetachedApp(["sh", "-c", `${prefix} ${escapedCmd}`], workDir, finalEnv);
            return;
        }

        if (prefix.length > 0)
            cmd = prefix.split(" ").concat(cmd);

        launchDetachedApp(cmd, workDir, finalEnv);
    }

    // * Session management
    function logout() {
        if (hasUwsm) {
            if (uwsmLogout.running)
                return;
            uwsmLogout.notRunning = false;
            uwsmLogout.running = true;
            return;
        }
        _logout();
    }

    function _logout() {
        if (SettingsData.customPowerActionLogout.length === 0) {
            if (CompositorService.isAqueous) {
                AqueousService.quit();
                return;
            }
            if (CompositorService.isNiri) {
                NiriService.quit();
                return;
            }

            if (CompositorService.isMango) {
                MangoService.quit();
                return;
            }

            if (CompositorService.isLabwc) {
                LabwcService.quit();
                return;
            }

            if (CompositorService.isSway || CompositorService.isScroll || CompositorService.isMiracle) {
                try {
                    I3.dispatch("exit");
                } catch (_) {}
                return;
            }

            HyprlandService.exit();
        } else {
            Quickshell.execDetached(customActionCommand(SettingsData.customPowerActionLogout));
        }
    }

    // systemd-run escapes the shell's cgroup so session teardown can't kill the command mid-run (#3250)
    function customActionCommand(cmd) {
        if (!userManagerAvailable)
            return ["sh", "-c", cmd];
        return ["systemd-run", "--user", "--scope", "--collect", "--quiet", "sh", "-c", cmd];
    }

    function powerManagerCommand(action) {
        if (isBSD)
            return bsdPowerCommand(action);
        const useLoginctl = isElogind || (loginctlCommandAvailable && !systemctlCommandAvailable);
        return [useLoginctl ? "loginctl" : "systemctl", action];
    }

    function bsdPowerCommand(action) {
        switch (action) {
        case "suspend":
        case "suspend-then-hibernate":
            return ["acpiconf", "-s", "3"];
        case "hibernate":
            return ["acpiconf", "-s", "4"];
        case "reboot":
            return ["shutdown", "-r", "now"];
        default:
            return ["shutdown", "-p", "now"];
        }
    }

    function suspend() {
        if (SettingsData.customPowerActionSuspend.length === 0) {
            Quickshell.execDetached(powerManagerCommand("suspend"));
        } else {
            Quickshell.execDetached(["sh", "-c", SettingsData.customPowerActionSuspend]);
        }
    }

    function hibernate() {
        hibernateProcess.errorOutput = "";
        if (SettingsData.customPowerActionHibernate.length > 0) {
            hibernateProcess.command = ["sh", "-c", SettingsData.customPowerActionHibernate];
        } else {
            hibernateProcess.command = powerManagerCommand("hibernate");
        }
        hibernateProcess.running = true;
    }

    function suspendThenHibernate() {
        Quickshell.execDetached(powerManagerCommand("suspend-then-hibernate"));
    }

    function suspendWithBehavior(behavior) {
        if (behavior === SettingsData.SuspendBehavior.Hibernate) {
            hibernate();
        } else if (behavior === SettingsData.SuspendBehavior.SuspendThenHibernate) {
            suspendThenHibernate();
        } else {
            suspend();
        }
    }

    function reboot() {
        if (SettingsData.customPowerActionReboot.length === 0) {
            Quickshell.execDetached(powerManagerCommand("reboot"));
        } else {
            Quickshell.execDetached(customActionCommand(SettingsData.customPowerActionReboot));
        }
    }

    function softReboot() {
        Quickshell.execDetached(["systemctl", "soft-reboot"]);
    }

    function poweroff() {
        if (SettingsData.customPowerActionPowerOff.length === 0) {
            Quickshell.execDetached(powerManagerCommand("poweroff"));
        } else {
            Quickshell.execDetached(customActionCommand(SettingsData.customPowerActionPowerOff));
        }
    }

    function isPowerActionSupported(action) {
        switch (action) {
        case "hibernate":
            return hibernateSupported;
        case "softreboot":
            return softRebootSupported;
        default:
            return true;
        }
    }

    function executePowerAction(action) {
        if (action.startsWith("custom:")) {
            const button = (SettingsData.customPowerButtons || [])[parseInt(action.slice(7), 10)];
            if (!button?.command)
                return false;
            Quickshell.execDetached(customActionCommand(button.command));
            return true;
        }
        switch (action) {
        case "logout":
            logout();
            return true;
        case "suspend":
            suspend();
            return true;
        case "hibernate":
            hibernate();
            return true;
        case "reboot":
            reboot();
            return true;
        case "softreboot":
            softReboot();
            return true;
        case "poweroff":
            poweroff();
            return true;
        case "restart":
            Quickshell.execDetached(["cyshell", "restart"]);
            return true;
        default:
            return false;
        }
    }

    function getPowerActionData(action) {
        if (action.startsWith("custom:")) {
            const button = (SettingsData.customPowerButtons || [])[parseInt(action.slice(7), 10)];
            return {
                "icon": button?.icon || "terminal",
                "label": button?.label || button?.command || "",
                "key": ""
            };
        }
        switch (action) {
        case "reboot":
            return {
                "icon": "restart_alt",
                "label": I18n.tr("Reboot", "verb, power menu action"),
                "key": "R"
            };
        case "softreboot":
            return {
                "icon": "autorenew",
                "label": I18n.tr("Soft reboot"),
                "key": "B"
            };
        case "logout":
            return {
                "icon": "logout",
                "label": I18n.tr("Log out"),
                "key": "X"
            };
        case "poweroff":
            return {
                "icon": "power_settings_new",
                "label": I18n.tr("Power off"),
                "key": "P"
            };
        case "lock":
            return {
                "icon": "lock",
                "label": I18n.tr("Lock", "verb, power menu action that locks the screen"),
                "key": "L"
            };
        case "suspend":
            return {
                "icon": "bedtime",
                "label": I18n.tr("Suspend", "verb, power menu action"),
                "key": "S"
            };
        case "hibernate":
            return {
                "icon": "ac_unit",
                "label": I18n.tr("Hibernate", "verb, power menu action"),
                "key": "H"
            };
        case "restart":
            return {
                "icon": "refresh",
                "label": I18n.tr("Restart CyShell"),
                "key": "D"
            };
        case "switchuser":
            return {
                "icon": "switch_account",
                "label": I18n.tr("Switch User"),
                "key": "U"
            };
        default:
            return {
                "icon": "help",
                "label": action,
                "key": "?"
            };
        }
    }

    // * Idle Inhibitor
    signal inhibitorChanged

    readonly property int _maxExpireInterval: 86400000

    Timer {
        id: inhibitExpireTimer
        repeat: false
        running: false
        onTriggered: root._armExpireTimer()
    }

    // Timers use a monotonic clock that stops across suspend, so the deadline is
    // re-checked against the wall clock on resume and after each chunk.
    function _armExpireTimer() {
        inhibitExpireTimer.stop();
        if (!idleInhibited || SessionData.idleInhibitedUntil <= 0)
            return;
        const remaining = SessionData.idleInhibitedUntil - Date.now();
        if (remaining <= 0) {
            disableIdleInhibit();
            return;
        }
        inhibitExpireTimer.interval = Math.min(remaining, _maxExpireInterval);
        inhibitExpireTimer.start();
    }

    onSessionResumed: _armExpireTimer()

    function _setIdleInhibited(enabled) {
        if (idleInhibited === enabled)
            return;
        idleInhibited = enabled;
        inhibitorChanged();
    }

    // Both entry points are deliberate: the singletons are created lazily in no fixed order, so
    // whichever of these runs once the session is loaded does the restore; the other no-ops.
    function _restoreIdleInhibit() {
        if (!SessionData._hasLoaded)
            return;
        _setIdleInhibited(SessionData.idleInhibited);
        _armExpireTimer();
    }

    Connections {
        target: SessionData

        function onLoaded() {
            root._restoreIdleInhibit();
        }
    }

    Component.onCompleted: _restoreIdleInhibit()

    function enableIdleInhibit(durationMinutes) {
        SessionData.setIdleInhibited(true, durationMinutes);
        _setIdleInhibited(true);
        _armExpireTimer();
    }

    function disableIdleInhibit() {
        SessionData.setIdleInhibited(false);
        _setIdleInhibited(false);
        _armExpireTimer();
    }

    function toggleIdleInhibit(durationMinutes) {
        if (idleInhibited) {
            disableIdleInhibit();
        } else {
            enableIdleInhibit(durationMinutes);
        }
    }

    function setInhibitReason(reason) {
        inhibitReason = reason;
    }

    Connections {
        target: CyShellService

        function onConnectionStateChanged() {
            if (CyShellService.isConnected) {
                checkDMSCapabilities();
            } else {
                clearPrepareForSleepSubscriptionState();
            }
        }

        function onCapabilitiesReceived() {
            syncSleepInhibitor();
        }
    }

    Connections {
        target: CyShellService
        enabled: CyShellService.isConnected

        function onCapabilitiesChanged() {
            checkDMSCapabilities();
        }

        function onDbusSignalReceived(subscriptionId, data) {
            if (subscriptionId !== prepareForSleepSubscriptionId) {
                return;
            }
            handlePrepareForSleepSignal(data);
        }
    }

    Connections {
        target: SettingsData

        function onLoginctlLockIntegrationChanged() {
            if (SettingsData.loginctlLockIntegration) {
                if (socketPath && socketPath.length > 0 && loginctlAvailable) {
                    if (!stateInitialized) {
                        stateInitialized = true;
                        getLoginctlState();
                        syncLockBeforeSuspend();
                    }
                }
            } else {
                stateInitialized = false;
            }
            syncSleepInhibitor();
        }

        function onLockBeforeSuspendChanged() {
            if (SettingsData.loginctlLockIntegration) {
                syncLockBeforeSuspend();
            }
            syncSleepInhibitor();
        }
    }

    Connections {
        target: CyShellService
        enabled: SettingsData.loginctlLockIntegration

        function onLoginctlStateUpdate(data) {
            updateLoginctlState(data);
        }
    }

    function checkDMSCapabilities() {
        if (!CyShellService.isConnected) {
            return;
        }

        if (CyShellService.capabilities.length === 0) {
            return;
        }

        if (CyShellService.capabilities.includes("loginctl")) {
            loginctlAvailable = true;
            if (SettingsData.loginctlLockIntegration && !stateInitialized) {
                stateInitialized = true;
                getLoginctlState();
                syncLockBeforeSuspend();
            }
        } else {
            loginctlAvailable = false;
            log.debug("loginctl capability not available in CyShell");
        }

        if (CyShellService.capabilities.includes("dbus")) {
            ensurePrepareForSleepSubscription();
        } else {
            clearPrepareForSleepSubscriptionState();
        }
    }

    function clearPrepareForSleepSubscriptionState() {
        prepareForSleepSubscriptionId = "";
        prepareForSleepSubscriptionPending = false;
    }

    function ensurePrepareForSleepSubscription() {
        if (!CyShellService.isConnected || !CyShellService.capabilities.includes("dbus")) {
            return;
        }

        if (prepareForSleepSubscriptionId || prepareForSleepSubscriptionPending) {
            return;
        }

        prepareForSleepSubscriptionPending = true;
        CyShellService.dbusSubscribe("system", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "PrepareForSleep", response => {
            prepareForSleepSubscriptionPending = false;

            if (response.error) {
                log.warn("Failed to subscribe to PrepareForSleep:", response.error);
                return;
            }

            prepareForSleepSubscriptionId = response.result?.subscriptionId || "";
        });
    }

    function emitSessionResumedOnce() {
        const now = Date.now();
        if ((now - lastResumeSignalTimestamp) < 1000) {
            return;
        }
        lastResumeSignalTimestamp = now;
        sessionResumed();
    }

    function handlePrepareForSleepSignal(data) {
        if (!data?.body || data.body.length === 0) {
            return;
        }

        const wasSleeping = preparingForSleep;
        preparingForSleep = data.body[0] === true;

        if (wasSleeping && !preparingForSleep) {
            emitSessionResumedOnce();
        }
    }

    function getLoginctlState() {
        if (!loginctlAvailable)
            return;
        CyShellService.sendRequest("loginctl.getState", null, response => {
            if (response.result) {
                updateLoginctlState(response.result);
            }
        });
    }

    function syncLockBeforeSuspend() {
        if (!loginctlAvailable)
            return;
        CyShellService.sendRequest("loginctl.setLockBeforeSuspend", {
            enabled: SettingsData.lockBeforeSuspend
        }, response => {
            if (response.error) {
                log.warn("Failed to sync lock before suspend:", response.error);
            } else {
                log.debug("Synced lock before suspend:", SettingsData.lockBeforeSuspend);
            }
        });
    }

    function syncSleepInhibitor() {
        if (!loginctlAvailable)
            return;
        if (!CyShellService.apiVersion || CyShellService.apiVersion < 4)
            return;
        CyShellService.sendRequest("loginctl.setSleepInhibitorEnabled", {
            enabled: SettingsData.loginctlLockIntegration && SettingsData.lockBeforeSuspend
        }, response => {
            if (response.error) {
                log.warn("Failed to sync sleep inhibitor:", response.error);
            } else {
                log.debug("Synced sleep inhibitor:", SettingsData.loginctlLockIntegration);
            }
        });
    }

    function updateLoginctlState(state) {
        const wasLocked = locked;
        const wasSleeping = preparingForSleep;

        sessionId = state.sessionId || "";
        sessionPath = state.sessionPath || "";
        locked = state.locked || false;
        active = state.active || false;
        idleHint = state.idleHint || false;
        lockedHint = state.lockedHint || false;
        preparingForSleep = state.preparingForSleep || false;
        sessionType = state.sessionType || "";
        userName = state.userName || "";
        seat = state.seat || "";
        display = state.display || "";

        if (locked && !wasLocked) {
            sessionLocked();
        } else if (!locked && wasLocked) {
            sessionUnlocked();
        }

        if (wasSleeping && !preparingForSleep) {
            emitSessionResumedOnce();
        }

        loginctlStateChanged();
    }
}
