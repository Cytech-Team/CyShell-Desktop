pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.I3
import qs.Common
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("KeyboardLayoutService")

    property int consumers: 0
    readonly property bool active: consumers > 0
    property string _polledLayout: ""
    property var _polledNames: []
    property int _polledCount: 0
    property int _polledIndex: -1
    property string _hyprlandKeyboard: ""
    property int _lastLayoutToggleSerial: 0
    property bool _labwcInitialized: false
    property bool _labwcProbeActive: false
    property int _labwcProbeAttempts: 0
    property int _labwcProbeFocusChecks: 0
    property string _labwcProbeText: ""
    property bool _labwcInternalTogglePending: false

    readonly property bool available: {
        switch (CompositorService.compositor) {
        case "aqueous":
        case "niri":
        case "mango":
        case "hyprland":
        case "sway":
        case "labwc":
            return true;
        default:
            return false;
        }
    }

    readonly property bool namesAreXkbCodes: CompositorService.compositor === "hyprland"

    readonly property var layoutNames: {
        switch (CompositorService.compositor) {
        case "aqueous":
            return AqueousService.keyboardLayouts;
        case "niri":
            return NiriService.keyboardLayoutNames || [];
        case "hyprland":
            return _polledNames;
        case "labwc":
            return ["us", "th"];
        default:
            return [];
        }
    }

    readonly property string currentLayout: {
        switch (CompositorService.compositor) {
        case "aqueous":
            return AqueousService.keyboardLayout;
        case "niri":
            return NiriService.getCurrentKeyboardLayoutName();
        case "mango":
            return MangoService.currentKeyboardLayout;
        case "hyprland":
        case "sway":
        case "labwc":
            return _polledLayout;
        default:
            return "";
        }
    }

    readonly property bool layoutKnown: currentLayout !== "" && currentLayout !== "Unknown"

    readonly property string compactLayout: {
        switch (CompositorService.compositor) {
        case "hyprland":
            return _polledNames.length > 0 ? (_polledNames[_polledIndex] ?? "") : _polledLayout;
        default:
            return currentLayout;
        }
    }

    readonly property int layoutCount: {
        switch (CompositorService.compositor) {
        case "aqueous":
            return AqueousService.keyboardLayouts.length;
        case "niri":
            return NiriService.keyboardLayoutNames.length;
        case "hyprland":
            return _polledCount;
        case "labwc":
            return 2;
        default:
            return 0;
        }
    }

    onActiveChanged: {
        if (active)
            refresh();
    }

    Connections {
        target: CyShellService
        function onLayoutToggleSerialChanged() {
            if (!CompositorService.isLabwc || !root._labwcInitialized) {
                root._lastLayoutToggleSerial = CyShellService.layoutToggleSerial;
                return;
            }
            const serial = CyShellService.layoutToggleSerial;
            if (serial === root._lastLayoutToggleSerial)
                return;

            const delta = Math.max(0, serial - root._lastLayoutToggleSerial);
            root._lastLayoutToggleSerial = serial;

            // Clicking the panel invokes cyshell-language, which itself emits
            // Alt+Shift. The helper callback already gives us the intended layout,
            // so do not flip a second time when evdev sees that synthetic combo.
            if (root._labwcInternalTogglePending) {
                root._labwcInternalTogglePending = false;
                labwcInternalToggleGuard.stop();
                return;
            }

            // If events were coalesced while QML was busy, only odd deltas change
            // the two-layout state. This keeps Panel state aligned after bursts.
            if ((delta % 2) === 1) {
                root._polledLayout = root._polledLayout === "th" ? "us" : "th";
                Quickshell.execDetached(["cyshell-language", "note", root._polledLayout === "th" ? "th" : "en"]);
            }
        }
    }

    Connections {
        target: CompositorService
        function onCompositorChanged() {
            if (root.active)
                root.refresh();
        }
    }

    Connections {
        target: root.active && CompositorService.isHyprland ? Hyprland : null
        enabled: root.active && CompositorService.isHyprland
        function onRawEvent(event) {
            if (event.name === "activelayout")
                root._pollHyprland();
        }
    }

    Loader {
        active: root.active && CompositorService.isSway
        sourceComponent: I3IpcListener {
            subscriptions: ["input"]
            onIpcEvent: event => {
                if (event.type !== "input")
                    return;
                try {
                    const payload = JSON.parse(event.data);
                    if (payload.change !== "xkb_layout")
                        return;
                    const name = payload.input && payload.input.xkb_active_layout_name;
                    if (name)
                        root._polledLayout = name;
                } catch (e) {}
            }
        }
    }

    function refresh() {
        switch (CompositorService.compositor) {
        case "hyprland":
            _pollHyprland();
            return;
        case "sway":
            _pollSway();
            return;
        case "labwc":
            _pollLabwc();
            return;
        }
    }

    function cycle() {
        switch (CompositorService.compositor) {
        case "niri":
            NiriService.cycleKeyboardLayout();
            return;
        case "aqueous":
            AqueousService.cycleKeyboardLayout();
            return;
        case "hyprland":
            Quickshell.execDetached(["hyprctl", "switchxkblayout", _hyprlandKeyboard, "next"]);
            _pollHyprland();
            return;
        case "mango":
            MangoService.cycleKeyboardLayout();
            return;
        case "sway":
            I3.dispatch("input type:keyboard xkb_switch_layout next");
            return;
        case "labwc":
            root._labwcInternalTogglePending = true;
            labwcInternalToggleGuard.restart();
            Proc.runCommand("keyboard-layout-labwc-toggle", ["cyshell-language", "toggle"], (output, exitCode) => {
                if (exitCode === 0) {
                    root._polledLayout = String(output || "").trim() === "th" ? "th" : "us";
                    Quickshell.execDetached(["cyshell-language", "note", root._polledLayout === "th" ? "th" : "en"]);
                } else {
                    root._labwcInternalTogglePending = false;
                    labwcInternalToggleGuard.stop();
                }
            });
            return;
        }
    }

    function _pollLabwc() {
        Proc.runCommand("keyboard-layout-labwc-status", ["cyshell-language", "status"], (output, exitCode) => {
            if (exitCode !== 0)
                return;
            const value = String(output || "").trim();
            root._polledLayout = value === "th" ? "th" : "us";
            root._lastLayoutToggleSerial = CyShellService.layoutToggleSerial;
            root._labwcInitialized = true;

            // Labwc does not expose the active XKB group through IPC. The persisted
            // value is normally correct, but CyShell may have been restarted while
            // the compositor stayed on another group. Probe the compositor once so
            // the panel starts from the layout that is actually producing text.
            if (root._labwcProbeAttempts === 0)
                labwcProbeDelay.restart();
        });
    }

    function _startLabwcProbe() {
        if (!CompositorService.isLabwc || root._labwcProbeActive || root._labwcProbeAttempts >= 3)
            return;
        root._labwcProbeAttempts++;
        root._labwcProbeFocusChecks = 0;
        root._labwcProbeText = "";
        root._labwcProbeActive = true;
    }

    function _finishLabwcProbe(text) {
        if (!root._labwcProbeActive)
            return;

        const value = String(text || "");
        let detected = "";
        if (/^[aA]$/.test(value))
            detected = "us";
        else if (/^[\u0E00-\u0E7F]$/.test(value))
            detected = "th";

        const retry = detected === "" && root._labwcProbeAttempts < 3;
        if (detected !== "") {
            root.log.info("Labwc layout probe detected", detected, "from", value);
            root._polledLayout = detected;
            root._lastLayoutToggleSerial = CyShellService.layoutToggleSerial;
            Quickshell.execDetached(["cyshell-language", "note", detected === "th" ? "th" : "en"]);
        } else {
            root.log.warn("Labwc layout probe did not receive a usable character (attempt", root._labwcProbeAttempts, ")");
        }
        root._labwcProbeActive = false;
        if (retry)
            labwcProbeRetry.restart();
    }

    function _pollSway() {
        Proc.runCommand("keyboard-layout-sway", ["swaymsg", "-t", "get_inputs", "-r"], (output, exitCode) => {
            if (exitCode !== 0)
                return;
            try {
                const keyboard = JSON.parse(output).find(i => i.type === "keyboard" && i.xkb_active_layout_name);
                if (keyboard)
                    root._polledLayout = keyboard.xkb_active_layout_name;
            } catch (e) {}
        });
    }

    function _pollHyprland() {
        Proc.runCommand("keyboard-layout-hyprland", ["hyprctl", "-j", "devices"], (output, exitCode) => {
            if (exitCode !== 0) {
                root._applyHyprlandKeyboard(null);
                return;
            }
            try {
                root._applyHyprlandKeyboard(JSON.parse(output).keyboards.find(kb => kb.main === true));
            } catch (e) {
                root._applyHyprlandKeyboard(null);
            }
        });
    }

    function _applyHyprlandKeyboard(keyboard) {
        if (!keyboard) {
            _hyprlandKeyboard = "";
            _polledNames = [];
            _polledCount = 0;
            _polledIndex = -1;
            _polledLayout = "Unknown";
            return;
        }
        const layouts = keyboard.layout ? keyboard.layout.split(",") : [];
        const variants = (keyboard.variant ?? "").split(",");
        const index = keyboard.active_layout_index;
        _hyprlandKeyboard = keyboard.name;
        _polledCount = layouts.length;
        _polledIndex = index === undefined ? -1 : index;
        _polledNames = index === undefined ? [] : layouts.map((layout, i) => variants[i] ? layout + "-" + variants[i] : layout);
        _polledLayout = keyboard.active_keymap || "Unknown";
    }
    Timer {
        id: labwcProbeDelay
        interval: 350
        repeat: false
        onTriggered: root._startLabwcProbe()
    }

    Timer {
        id: labwcProbeRetry
        interval: 250
        repeat: false
        onTriggered: root._startLabwcProbe()
    }

    Timer {
        id: labwcInternalToggleGuard
        interval: 500
        repeat: false
        onTriggered: root._labwcInternalTogglePending = false
    }

    LazyLoader {
        id: labwcProbeLoader
        active: root._labwcProbeActive

        PanelWindow {
            id: labwcProbeWindow
            visible: true
            color: "transparent"
            implicitWidth: 1
            implicitHeight: 1

            anchors {
                top: true
                left: true
            }

            WlrLayershell.namespace: "cyshell:keyboard-layout-probe"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            FocusScope {
                id: labwcProbeFocus
                anchors.fill: parent
                focus: true

                Keys.onPressed: event => {
                    const text = String(event.text || "");
                    if (text.length === 0)
                        return;
                    // Qt.Key_* changes with the active layout, so detect from the
                    // translated text rather than requiring Qt.Key_A.
                    root._labwcProbeText = text;
                    event.accepted = true;
                    labwcProbeFinish.restart();
                }

                Keys.onReleased: event => {
                    if (root._labwcProbeText !== "")
                        event.accepted = true;
                }
            }

            Timer {
                id: labwcProbeFocusWait
                interval: 50
                repeat: true
                running: true
                onTriggered: {
                    labwcProbeFocus.forceActiveFocus();
                    root._labwcProbeFocusChecks++;
                    if (labwcProbeFocus.activeFocus) {
                        stop();
                        labwcProbeInject.restart();
                    } else if (root._labwcProbeFocusChecks >= 10) {
                        stop();
                        root._finishLabwcProbe("");
                    }
                }
            }

            Timer {
                id: labwcProbeInject
                interval: 100
                repeat: false
                onTriggered: Quickshell.execDetached(["/usr/bin/ydotool", "key", "30:1", "30:0"])
            }

            Timer {
                id: labwcProbeFinish
                interval: 80
                repeat: false
                onTriggered: root._finishLabwcProbe(root._labwcProbeText)
            }

            Timer {
                interval: 700
                repeat: false
                running: true
                onTriggered: root._finishLabwcProbe("")
            }
        }
    }

}
