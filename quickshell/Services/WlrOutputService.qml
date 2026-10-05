pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "../Common/OutputModel.js" as OutputModel

Singleton {
    id: root
    readonly property var log: Log.scoped("WlrOutputService")

    property bool wlrOutputAvailable: false
    property var outputs: []
    property int serial: 0

    signal stateChanged
    signal configurationApplied(bool success, string message)

    property bool savedRestoreAttempted: false
    property string restoredTopologyKey: ""

    Timer {
        id: savedRestoreTimer
        interval: 650
        repeat: false
        onTriggered: root.restoreSavedConfiguration()
    }

    Connections {
        target: CyShellService

        function onCapabilitiesReceived() {
            checkCapabilities();
        }

        function onConnectionStateChanged() {
            if (CyShellService.isConnected) {
                checkCapabilities();
                return;
            }
            wlrOutputAvailable = false;
            savedRestoreAttempted = false;
            restoredTopologyKey = "";
            savedRestoreTimer.stop();
        }

        function onWlrOutputStateUpdate(data) {
            if (!wlrOutputAvailable) {
                return;
            }
            handleStateUpdate(data);
        }
    }

    Component.onCompleted: {
        if (!CyShellService.backendAvailable) {
            return;
        }
        checkCapabilities();
    }

    function checkCapabilities() {
        if (!CyShellService.capabilities || !Array.isArray(CyShellService.capabilities)) {
            wlrOutputAvailable = false;
            return;
        }

        const hasWlrOutput = CyShellService.capabilities.includes("wlroutput");
        if (hasWlrOutput && !wlrOutputAvailable) {
            wlrOutputAvailable = true;
            log.info("wlr-output-management capability detected");
            requestState();
            return;
        }

        if (!hasWlrOutput) {
            wlrOutputAvailable = false;
        }
    }

    function requestState() {
        if (!CyShellService.isConnected || !wlrOutputAvailable) {
            return;
        }

        CyShellService.sendRequest("wlroutput.getState", null, response => {
            if (!response.result) {
                return;
            }
            handleStateUpdate(response.result);
        });
    }

    function handleStateUpdate(state) {
        outputs = state.outputs || [];
        serial = state.serial || 0;

        if (outputs.length === 0) {
            log.warn("Received empty outputs list");
        } else {
            log.debug("Updated with", outputs.length, "outputs, serial:", serial);
            outputs.forEach((output, index) => {
                log.debug("Output", index, "-", output.name, "enabled:", output.enabled, "mode:", output.currentMode ? output.currentMode.width + "x" + output.currentMode.height + "@" + (output.currentMode.refresh / 1000) + "Hz" : "none");
            });
        }
        stateChanged();

        const topology = outputTopologyKey();
        if (outputs.length > 0 && topology !== restoredTopologyKey) {
            restoredTopologyKey = topology;
            savedRestoreAttempted = false;
            savedRestoreTimer.restart();
        }
    }

    function outputTopologyKey() {
        return (outputs || []).map(output => {
            return [
                String(output.name || ""),
                String(output.serialNumber || ""),
                String(output.make || ""),
                String(output.model || "")
            ].join("|");
        }).sort().join(";");
    }

    function _currentHead(output) {
        const head = {
            "name": output.name,
            "enabled": output.enabled !== false
        };

        if (!head.enabled)
            return head;

        const current = output.currentMode
            || (output.modes || []).find(mode => mode.preferred)
            || output.modes?.[0]
            || null;

        if (current?.id !== undefined)
            head.modeId = current.id;

        head.position = {
            "x": output.x ?? 0,
            "y": output.y ?? 0
        };
        head.scale = output.scale > 0 ? output.scale : 1.0;
        head.transform = output.transform ?? 0;
        if (output.adaptiveSyncSupported)
            head.adaptiveSync = output.adaptiveSync ?? 0;
        return head;
    }

    function _savedOutputForLive(savedOutputs, live) {
        if (!savedOutputs || !live)
            return null;

        if (savedOutputs[live.name])
            return savedOutputs[live.name];

        const entries = Object.values(savedOutputs);
        if (live.serialNumber) {
            const serialMatches = entries.filter(entry => entry?.serialNumber
                && entry.serialNumber === live.serialNumber);
            if (serialMatches.length === 1)
                return serialMatches[0];
        }

        if (live.make && live.model) {
            const modelMatches = entries.filter(entry => entry?.make === live.make
                && entry?.model === live.model);
            if (modelMatches.length === 1)
                return modelMatches[0];
        }

        return null;
    }

    function _modeForSaved(output, savedMode) {
        const modes = output?.modes || [];
        if (!savedMode)
            return output?.currentMode || modes.find(mode => mode.preferred) || modes[0] || null;

        let exact = modes.find(mode => mode.width === savedMode.width
            && mode.height === savedMode.height
            && Math.abs((mode.refresh || 0) - (savedMode.refresh || 0)) <= 2);
        if (exact)
            return exact;

        const sameResolution = modes.filter(mode => mode.width === savedMode.width
            && mode.height === savedMode.height);
        if (sameResolution.length > 0) {
            sameResolution.sort((a, b) => Math.abs((a.refresh || 0) - (savedMode.refresh || 0))
                - Math.abs((b.refresh || 0) - (savedMode.refresh || 0)));
            return sameResolution[0];
        }

        return output?.currentMode || modes.find(mode => mode.preferred) || modes[0] || null;
    }

    function _restoreHeads(savedConfig) {
        const savedOutputs = savedConfig?.outputs || {};
        const heads = [];

        for (const output of (outputs || [])) {
            const saved = _savedOutputForLive(savedOutputs, output);
            if (!saved) {
                heads.push(_currentHead(output));
                continue;
            }

            const head = {
                "name": output.name,
                "enabled": saved.enabled !== false
            };

            if (head.enabled) {
                const mode = _modeForSaved(output, saved.mode);
                if (mode?.id !== undefined)
                    head.modeId = mode.id;
                head.position = {
                    "x": saved.position?.x ?? output.x ?? 0,
                    "y": saved.position?.y ?? output.y ?? 0
                };
                head.scale = saved.scale > 0 ? saved.scale : (output.scale > 0 ? output.scale : 1.0);
                head.transform = saved.transform ?? output.transform ?? 0;
                if (output.adaptiveSyncSupported)
                    head.adaptiveSync = saved.adaptiveSync ?? output.adaptiveSync ?? 0;
            }

            heads.push(head);
        }

        return heads;
    }

    function _headsMatchCurrent(heads) {
        for (const head of heads) {
            const output = getOutput(head.name);
            if (!output)
                return false;
            if (!!head.enabled !== (output.enabled !== false))
                return false;
            if (!head.enabled)
                continue;

            if (head.modeId !== undefined && output.currentMode?.id !== head.modeId)
                return false;
            if ((head.position?.x ?? output.x ?? 0) !== (output.x ?? 0)
                || (head.position?.y ?? output.y ?? 0) !== (output.y ?? 0))
                return false;
            if (Math.abs((head.scale ?? 1) - (output.scale > 0 ? output.scale : 1)) > 0.005)
                return false;
            if ((head.transform ?? 0) !== (output.transform ?? 0))
                return false;
            if (output.adaptiveSyncSupported
                && (head.adaptiveSync ?? 0) !== (output.adaptiveSync ?? 0))
                return false;
        }
        return true;
    }

    function restoreSavedConfiguration() {
        if (savedRestoreAttempted)
            return;
        savedRestoreAttempted = true;

        const saved = SettingsData.labwcDisplayConfiguration;
        if (!saved || saved.version !== 1 || !saved.outputs
            || Object.keys(saved.outputs).length === 0)
            return;

        const heads = _restoreHeads(saved);
        if (heads.length === 0 || !heads.some(head => head.enabled)
            || _headsMatchCurrent(heads))
            return;

        log.info("Restoring saved Labwc display configuration for", heads.length, "outputs");
        testConfiguration(heads, (testSuccess, testMessage) => {
            if (!testSuccess) {
                log.warn("Saved display configuration no longer validates:", testMessage);
                return;
            }
            applyConfiguration(heads, (success, message) => {
                if (!success)
                    log.warn("Failed to restore saved display configuration:", message);
                else
                    log.info("Saved display configuration restored");
            });
        });
    }

    function getOutput(name) {
        for (const output of outputs) {
            if (output.name === name) {
                return output;
            }
        }
        return null;
    }

    function applyConfiguration(heads, callback) {
        if (!CyShellService.isConnected || !wlrOutputAvailable) {
            if (callback) {
                callback(false, I18n.tr("Not connected"));
            }
            return;
        }

        log.debug("Applying configuration for", heads.length, "outputs");
        heads.forEach((head, index) => {
            log.debug("Head", index, "- name:", head.name, "enabled:", head.enabled, "modeId:", head.modeId, "customMode:", JSON.stringify(head.customMode), "position:", JSON.stringify(head.position), "scale:", head.scale, "transform:", head.transform, "adaptiveSync:", head.adaptiveSync);
        });

        CyShellService.sendRequest("wlroutput.applyConfiguration", {
            "heads": heads
        }, response => {
            const success = !response.error && response.result?.success === true;
            const message = response.error || response.result?.message || "";

            if (!success) {
                log.warn("applyConfiguration error:", message);
            } else {
                log.debug("Configuration applied successfully");
            }

            configurationApplied(success, message);
            if (callback) {
                callback(success, message);
            }
        }, 5000);
    }

    function testConfiguration(heads, callback) {
        if (!CyShellService.isConnected || !wlrOutputAvailable) {
            if (callback) {
                callback(false, I18n.tr("Not connected"));
            }
            return;
        }

        log.debug("Testing configuration for", heads.length, "outputs");

        CyShellService.sendRequest("wlroutput.testConfiguration", {
            "heads": heads
        }, response => {
            const success = !response.error && response.result?.success === true;
            const message = response.error || response.result?.message || "";

            if (!success) {
                log.warn("testConfiguration error:", message);
            } else {
                log.debug("Configuration test passed");
            }

            if (callback) {
                callback(success, message);
            }
        }, 5000);
    }

    function applyOutputsConfig(outputsData, connectedOutputs, callback) {
        if (!wlrOutputAvailable) {
            if (callback)
                callback(false, I18n.tr("Not connected"));
            return;
        }
        const heads = outputsConfigHeads(outputsData, connectedOutputs);
        if (heads.length === 0) {
            if (callback)
                callback(false, I18n.tr("No monitors"));
            return;
        }
        applyConfiguration(heads, callback);
    }

    function outputsConfigHeads(outputsData, connectedOutputs) {
        const heads = [];
        for (const name in outputsData) {
            if (!connectedOutputs[name])
                continue;
            const output = outputsData[name];
            const mode = (output.modes && output.current_mode >= 0) ? output.modes[output.current_mode] : null;
            const enabled = !!mode;
            const head = {
                "name": name,
                "enabled": enabled
            };

            if (enabled) {
                if (mode.id !== undefined)
                    head.modeId = mode.id;
                else
                    head.customMode = {
                        "width": mode.width,
                        "height": mode.height,
                        "refresh": mode.refresh_rate
                    };

                if (output.logical) {
                    head.position = {
                        "x": output.logical.x ?? 0,
                        "y": output.logical.y ?? 0
                    };
                    head.scale = output.logical.scale ?? 1.0;
                    head.transform = OutputModel.transformIndex(output.logical.transform);
                }
            }
            heads.push(head);
        }

        return heads;
    }

    Connections {
        target: SessionService

        function onSessionResumed() {
            log.info("Session resumed, re-requesting output state, current outputs:", outputs.length);
            requestState();
        }
    }
}
