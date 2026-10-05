pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

Singleton {
    id: root

    readonly property var log: Log.scoped("LaptopLidService")
    readonly property string upowerService: "org.freedesktop.UPower"
    readonly property string upowerPath: "/org/freedesktop/UPower"
    readonly property string upowerInterface: "org.freedesktop.UPower"
    readonly property string propertiesInterface: "org.freedesktop.DBus.Properties"
    readonly property bool dbusAvailable: CyShellService.isConnected
        && (CyShellService.capabilities || []).includes("dbus")

    property bool lidPresent: false
    property bool lidClosed: false
    property bool stateKnown: false
    property bool subscribed: false
    property bool _changingPrimary: false

    readonly property string internalOutputName: findInternalOutputName()
    readonly property string failoverTarget: String(SettingsData.displayLidFailoverTarget || "")
    readonly property string restoreTarget: String(SettingsData.displayLidPrimaryRestore || "")

    Component.onCompleted: {
        setupBackend();
    }

    Connections {
        target: CyShellService

        function onConnectionStateChanged() {
            root.subscribed = false;
            root.setupBackend();
        }

        function onCapabilitiesReceived() {
            root.setupBackend();
        }

        function onDbusSignalReceived(subscriptionId, data) {
            root.handleDbusSignal(data);
        }
    }

    Connections {
        target: SettingsData

        function onPrimaryDisplayNameChanged() {
            if (!root.lidClosed || root._changingPrimary)
                return;

            const current = String(SettingsData.primaryDisplayName || "");
            if (SettingsData.displayAutoPrimaryOnLidClose
                    && root.isInternalOutputName(current)) {
                Qt.callLater(root.applyClosedLidPolicy);
                return;
            }

            const expected = String(SettingsData.displayLidFailoverTarget || "");
            if (expected && current !== expected)
                root.clearRestoreState();
        }

        function onDisplayAutoPrimaryOnLidCloseChanged() {
            if (!SettingsData.displayAutoPrimaryOnLidClose)
                root.clearRestoreState();
            else if (root.lidClosed)
                root.applyClosedLidPolicy();
        }
    }

    Connections {
        target: WlrOutputService

        function onStateChanged() {
            if (root.lidClosed && SettingsData.displayAutoPrimaryOnLidClose)
                root.applyClosedLidPolicy();
        }
    }

    Timer {
        interval: 750
        repeat: true
        running: root.lidClosed && SettingsData.displayAutoPrimaryOnLidClose
        onTriggered: root.applyClosedLidPolicy()
    }

    Timer {
        id: procFallbackTimer
        interval: 1000
        repeat: true
        running: !root.dbusAvailable
        triggeredOnStart: true
        onTriggered: {
            if (!lidProbe.running)
                lidProbe.running = true;
        }
    }

    Process {
        id: lidProbe
        command: ["bash", "-lc", "f=$(find /proc/acpi/button/lid -mindepth 2 -maxdepth 2 -type f -name state 2>/dev/null | head -n1); [ -n \"$f\" ] || exit 2; cat \"$f\""]
        stdout: StdioCollector {}
        onExited: exitCode => {
            if (exitCode !== 0)
                return;
            const value = String(stdout.text || "").toLowerCase();
            root.lidPresent = true;
            root.applyLidState(value.includes("closed"));
        }
    }

    function setupBackend() {
        if (!dbusAvailable)
            return;
        if (!subscribed) {
            subscribed = true;
            CyShellService.dbusSubscribe(
                "system",
                upowerService,
                upowerPath,
                propertiesInterface,
                "PropertiesChanged",
                null
            );
        }
        queryProperty("LidIsPresent", value => {
            lidPresent = value === true;
        });
        queryProperty("LidIsClosed", value => {
            if (typeof value === "boolean")
                applyLidState(value);
        });
    }

    function unwrapDbusValue(value) {
        if (value === null || value === undefined)
            return value;
        if (typeof value === "object") {
            if (value.value !== undefined)
                return unwrapDbusValue(value.value);
            if (Array.isArray(value.values) && value.values.length > 0)
                return unwrapDbusValue(value.values[0]);
        }
        return value;
    }

    function queryProperty(name, callback) {
        CyShellService.dbusCall(
            "system",
            upowerService,
            upowerPath,
            propertiesInterface,
            "Get",
            [upowerInterface, name],
            response => {
                if (response.error || !response.result)
                    return;
                const values = response.result.values || [];
                callback(unwrapDbusValue(values[0]));
            }
        );
    }

    function handleDbusSignal(data) {
        if (!data || data.path !== upowerPath || data.member !== "PropertiesChanged")
            return;
        const body = data.body || [];
        if (String(body[0] || "") !== upowerInterface)
            return;

        const changed = body[1] || {};
        if (changed.LidIsPresent !== undefined)
            lidPresent = unwrapDbusValue(changed.LidIsPresent) === true;
        if (changed.LidIsClosed !== undefined)
            applyLidState(unwrapDbusValue(changed.LidIsClosed) === true);
    }

    function isInternalOutputName(name) {
        const value = String(name || "").toUpperCase();
        return value.startsWith("EDP-")
            || value.startsWith("LVDS-")
            || value.startsWith("DSI-");
    }

    function isVirtualOutput(output) {
        const name = String(output?.name || "");
        const description = String(output?.description || "").toLowerCase();
        return name.startsWith("HEADLESS-") || description.includes("headless");
    }

    function findInternalOutputName() {
        void WlrOutputService.outputs;
        for (const output of (WlrOutputService.outputs || [])) {
            if (isInternalOutputName(output?.name))
                return String(output.name);
        }
        for (const screen of (Quickshell.screens || [])) {
            if (isInternalOutputName(screen?.name))
                return String(screen.name);
        }
        return "";
    }

    function outputAvailable(name) {
        if (!name)
            return false;
        const output = WlrOutputService.getOutput(name);
        if (output)
            return output.enabled !== false;
        return (Quickshell.screens || []).some(screen => screen?.name === name);
    }

    function externalCandidates() {
        const candidates = (WlrOutputService.outputs || []).filter(output => {
            return output
                && output.enabled !== false
                && !isInternalOutputName(output.name)
                && !isVirtualOutput(output);
        });
        candidates.sort((a, b) => {
            const ax = a.x ?? 0;
            const bx = b.x ?? 0;
            if (ax !== bx)
                return ax - bx;
            return (a.y ?? 0) - (b.y ?? 0);
        });
        return candidates;
    }

    function setPrimary(name) {
        if (!name || String(SettingsData.primaryDisplayName || "") === name)
            return;
        _changingPrimary = true;
        SettingsData.set("primaryDisplayName", name);
        SettingsData.saveSettings();
        _changingPrimary = false;
    }

    function clearRestoreState() {
        _changingPrimary = true;
        SettingsData.set("displayLidPrimaryRestore", "");
        SettingsData.set("displayLidFailoverTarget", "");
        SettingsData.saveSettings();
        _changingPrimary = false;
    }

    function applyLidState(closed) {
        const next = !!closed;
        const changed = !stateKnown || next !== lidClosed;
        lidClosed = next;
        stateKnown = true;
        if (!changed)
            return;

        log.info("Laptop lid state:", next ? "closed" : "open");
        if (next)
            applyClosedLidPolicy();
        else
            applyOpenLidPolicy();
    }

    function applyClosedLidPolicy() {
        if (!SettingsData.displayAutoPrimaryOnLidClose)
            return;

        const internal = internalOutputName;
        if (!internal)
            return;

        const current = String(SettingsData.primaryDisplayName || "");
        const savedRestore = String(SettingsData.displayLidPrimaryRestore || "");
        const savedFailover = String(SettingsData.displayLidFailoverTarget || "");

        // Shell restarted while the lid was already closed. Keep the existing
        // external failover target so opening the lid can still restore it.
        if (savedRestore && savedFailover && current === savedFailover)
            return;

        if (current !== internal)
            return;

        const candidates = externalCandidates();
        if (candidates.length === 0)
            return;

        const target = String(candidates[0].name);
        _changingPrimary = true;
        SettingsData.set("displayLidPrimaryRestore", internal);
        SettingsData.set("displayLidFailoverTarget", target);
        SettingsData.set("primaryDisplayName", target);
        SettingsData.saveSettings();
        _changingPrimary = false;

        log.info("Main display failed over from", internal, "to", target, "because the lid closed");
    }

    function applyOpenLidPolicy() {
        const restore = String(SettingsData.displayLidPrimaryRestore || "");
        const failover = String(SettingsData.displayLidFailoverTarget || "");

        if (!restore) {
            clearRestoreState();
            return;
        }

        if (SettingsData.displayRestorePrimaryOnLidOpen
                && outputAvailable(restore)
                && (!failover || String(SettingsData.primaryDisplayName || "") === failover)) {
            setPrimary(restore);
            log.info("Restored main display to", restore, "after lid opened");
        }

        clearRestoreState();
    }
}
