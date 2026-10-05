pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

Singleton {
    id: root

    readonly property var log: Log.scoped("DisplayConfigState")
    readonly property bool hasOutputBackend: WlrOutputService.wlrOutputAvailable
    property var pendingChanges: ({})
    property var originalHeads: []
    property var appliedHeads: []
    property var appliedSnapshot: null
    property var appliedOutputNames: []
    property bool applying: false

    readonly property var outputs: buildOutputMap(false)
    readonly property var allOutputs: buildOutputMap(true)
    readonly property bool hasPendingChanges: Object.keys(pendingChanges || {}).length > 0
    readonly property string effectivePrimaryName: resolvePrimaryDisplayName()
    readonly property var primaryOptions: buildPrimaryOptions()

    signal changesApplied(var changeDescriptions)
    signal changesConfirmed
    signal changesReverted
    signal applyFailed(string message)

    Connections {
        target: WlrOutputService
        function onStateChanged() {
            if (!root.hasPendingChanges)
                root.pendingChanges = ({});
        }
    }

    function clone(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function rawOutput(outputName) {
        return (WlrOutputService.outputs || []).find(output => output.name === outputName) || null;
    }

    function isVirtualOutput(output) {
        const name = String(output?.name || "");
        const description = String(output?.description || "").toLowerCase();
        return name.startsWith("HEADLESS-") || description.includes("headless");
    }

    function normalizedOutput(raw) {
        if (!raw)
            return null;

        const modes = Array.isArray(raw.modes) ? raw.modes.map(mode => ({
                    id: mode.id,
                    width: mode.width,
                    height: mode.height,
                    refresh: mode.refresh,
                    preferred: mode.preferred === true
                })) : [];

        let currentIndex = -1;
        if (raw.currentMode) {
            currentIndex = modes.findIndex(mode => mode.id === raw.currentMode.id);
            if (currentIndex < 0) {
                currentIndex = modes.findIndex(mode => mode.width === raw.currentMode.width
                        && mode.height === raw.currentMode.height
                        && Math.abs((mode.refresh || 0) - (raw.currentMode.refresh || 0)) <= 2);
            }
        }

        if (currentIndex < 0 && modes.length > 0)
            currentIndex = Math.max(0, modes.findIndex(mode => mode.preferred));

        const scale = raw.scale > 0 ? raw.scale : 1.0;

        return {
            name: raw.name,
            description: raw.description || "",
            make: raw.make || "",
            model: raw.model || "",
            serialNumber: raw.serialNumber || "",
            physicalWidth: raw.physicalWidth || 0,
            physicalHeight: raw.physicalHeight || 0,
            connected: true,
            enabled: raw.enabled !== false,
            modes,
            current_mode: currentIndex,
            vrr_supported: raw.adaptiveSyncSupported === true,
            vrr_enabled: raw.adaptiveSync === 1,
            logical: {
                x: raw.x ?? 0,
                y: raw.y ?? 0,
                scale,
                transform: raw.transform ?? 0
            }
        };
    }

    function applyPendingToOutput(outputName, output) {
        if (!output)
            return output;

        const changes = pendingChanges?.[outputName];
        if (!changes)
            return output;

        const result = clone(output);

        if (changes.enabled !== undefined)
            result.enabled = changes.enabled;

        if (changes.modeId !== undefined) {
            const modeIndex = result.modes.findIndex(mode => mode.id === changes.modeId);
            if (modeIndex >= 0)
                result.current_mode = modeIndex;
        }

        if (changes.position) {
            result.logical.x = changes.position.x;
            result.logical.y = changes.position.y;
        }

        if (changes.scale !== undefined)
            result.logical.scale = changes.scale;

        if (changes.transform !== undefined)
            result.logical.transform = changes.transform;

        if (changes.vrr !== undefined)
            result.vrr_enabled = changes.vrr;

        return result;
    }

    function buildOutputMap(withPending) {
        void WlrOutputService.outputs;
        void pendingChanges;

        const result = {};
        for (const raw of (WlrOutputService.outputs || [])) {
            let output = normalizedOutput(raw);
            if (withPending)
                output = applyPendingToOutput(raw.name, output);
            result[raw.name] = output;
        }
        return result;
    }

    function getOutputDisplayName(output, outputName) {
        if (!output)
            return outputName;
        if (isVirtualOutput(output)) {
            const match = String(outputName || "").match(/(\d+)$/);
            return match ? I18n.tr("Agent Workspace %1").arg(match[1]) : I18n.tr("Agent Workspace");
        }
        const model = String(output.model || "").trim();
        const make = String(output.make || "").trim();
        if (model)
            return model + " (" + outputName + ")";
        if (make)
            return make + " (" + outputName + ")";
        return outputName;
    }

    function buildPrimaryOptions() {
        void allOutputs;
        const names = Object.keys(allOutputs || {}).filter(name => allOutputs[name]?.connected && allOutputs[name]?.enabled);
        const physical = names.filter(name => !isVirtualOutput(allOutputs[name]));
        const source = physical.length > 0 ? physical : names;
        return source.map(name => getOutputDisplayName(allOutputs[name], name));
    }

    function outputNameForDisplayLabel(label) {
        for (const name of Object.keys(allOutputs || {})) {
            if (getOutputDisplayName(allOutputs[name], name) === label)
                return name;
        }
        return "";
    }

    function resolvePrimaryDisplayName() {
        void SettingsData.primaryDisplayName;
        void allOutputs;

        const configured = String(SettingsData.primaryDisplayName || "");
        if (configured && allOutputs[configured]?.enabled)
            return configured;

        const candidates = Object.keys(allOutputs || {}).filter(name => allOutputs[name]?.enabled);
        const physical = candidates.filter(name => !isVirtualOutput(allOutputs[name]));
        const source = physical.length > 0 ? physical : candidates;

        source.sort((a, b) => {
            const ao = allOutputs[a];
            const bo = allOutputs[b];
            const ax = ao?.logical?.x ?? 0;
            const bx = bo?.logical?.x ?? 0;
            if (ax !== bx)
                return ax - bx;
            return (ao?.logical?.y ?? 0) - (bo?.logical?.y ?? 0);
        });

        return source[0] || "";
    }

    function setPrimaryDisplay(outputName) {
        if (!outputName || !allOutputs[outputName]?.enabled)
            return;
        SettingsData.set("primaryDisplayName", outputName);
        SettingsData.saveSettings();
    }

    function currentMode(output) {
        if (!output?.modes || output.current_mode < 0 || output.current_mode >= output.modes.length)
            return null;
        return output.modes[output.current_mode];
    }

    function preferredMode(output) {
        return output?.modes?.find(mode => mode.preferred) || output?.modes?.[0] || null;
    }

    function modeForOutputName(outputName) {
        return currentMode(allOutputs[outputName]) || preferredMode(allOutputs[outputName]);
    }

    function formatRefresh(refresh) {
        if (!(refresh > 0))
            return "";
        let text = (refresh / 1000).toFixed(3);
        text = text.replace(/0+$/, "").replace(/\.$/, "");
        return text + " Hz";
    }

    function formatMode(mode) {
        if (!mode)
            return I18n.tr("Auto");
        const refresh = formatRefresh(mode.refresh);
        return mode.width + " × " + mode.height + (refresh ? " @ " + refresh : "") + (mode.preferred ? " · " + I18n.tr("Recommended") : "");
    }

    function modeOptions(outputName) {
        const output = allOutputs[outputName];
        if (!output?.modes)
            return [];

        const seen = {};
        const result = [];
        for (const mode of output.modes) {
            const key = mode.width + "x" + mode.height + "@" + mode.refresh;
            if (seen[key])
                continue;
            seen[key] = true;
            result.push(formatMode(mode));
        }
        return result;
    }

    function modeIdForLabel(outputName, label) {
        const output = allOutputs[outputName];
        if (!output?.modes)
            return undefined;
        for (const mode of output.modes) {
            if (formatMode(mode) === label)
                return mode.id;
        }
        return undefined;
    }

    function formatResolution(mode) {
        return mode ? mode.width + " × " + mode.height : "";
    }

    function resolutionOptions(outputName) {
        const output = allOutputs[outputName];
        if (!output?.modes)
            return [];
        const seen = {};
        const values = [];
        for (const mode of output.modes) {
            const label = formatResolution(mode);
            if (!seen[label]) {
                seen[label] = true;
                values.push({
                    label,
                    width: mode.width,
                    height: mode.height
                });
            }
        }
        values.sort((a, b) => (b.width * b.height) - (a.width * a.height));
        return values.map(value => value.label);
    }

    function modeIdForResolution(outputName, label) {
        const output = allOutputs[outputName];
        if (!output?.modes)
            return undefined;

        const parts = String(label).split("×").map(part => parseInt(part.trim()));
        if (parts.length !== 2 || isNaN(parts[0]) || isNaN(parts[1]))
            return undefined;

        const candidates = output.modes.filter(mode => mode.width === parts[0] && mode.height === parts[1]);
        if (candidates.length === 0)
            return undefined;

        const current = currentMode(output);
        const currentRefresh = current?.refresh || 0;
        candidates.sort((a, b) => {
            if (a.preferred !== b.preferred && currentRefresh === 0)
                return a.preferred ? -1 : 1;
            return Math.abs((a.refresh || 0) - currentRefresh) - Math.abs((b.refresh || 0) - currentRefresh);
        });
        return candidates[0].id;
    }

    function refreshOptions(outputName) {
        const output = allOutputs[outputName];
        const selected = currentMode(output) || preferredMode(output);
        if (!selected || !output?.modes)
            return [];

        const seen = {};
        const values = [];
        for (const mode of output.modes) {
            if (mode.width !== selected.width || mode.height !== selected.height)
                continue;
            const label = formatRefresh(mode.refresh);
            if (!seen[label]) {
                seen[label] = true;
                values.push({
                    label,
                    refresh: mode.refresh
                });
            }
        }
        values.sort((a, b) => b.refresh - a.refresh);
        return values.map(value => value.label);
    }

    function modeIdForRefresh(outputName, label) {
        const output = allOutputs[outputName];
        const selected = currentMode(output) || preferredMode(output);
        if (!selected || !output?.modes)
            return undefined;

        for (const mode of output.modes) {
            if (mode.width === selected.width
                && mode.height === selected.height
                && formatRefresh(mode.refresh) === label)
                return mode.id;
        }
        return undefined;
    }

    function formatScale(scale) {
        return Math.round((scale || 1) * 100) + "%";
    }

    function scaleOptions(outputName) {
        const output = allOutputs[outputName];
        const current = output?.logical?.scale || 1;
        const values = [0.75, 1, 1.1, 1.2, 1.25, 1.35, 1.5, 1.75, 2, 2.25, 2.5, 3];
        if (!values.some(value => Math.abs(value - current) < 0.005))
            values.push(current);
        values.sort((a, b) => a - b);
        return values.map(formatScale);
    }

    function scaleForLabel(label) {
        const value = parseFloat(String(label).replace("%", ""));
        return isNaN(value) ? NaN : value / 100;
    }

    function getTransformLabel(transform) {
        switch (Number(transform)) {
        case 1:
            return "90°";
        case 2:
            return "180°";
        case 3:
            return "270°";
        case 4:
            return I18n.tr("Flipped");
        case 5:
            return I18n.tr("Flipped 90°");
        case 6:
            return I18n.tr("Flipped 180°");
        case 7:
            return I18n.tr("Flipped 270°");
        default:
            return I18n.tr("Normal");
        }
    }

    function getTransformValue(label) {
        if (label === "90°")
            return 1;
        if (label === "180°")
            return 2;
        if (label === "270°")
            return 3;
        if (label === I18n.tr("Flipped"))
            return 4;
        if (label === I18n.tr("Flipped 90°"))
            return 5;
        if (label === I18n.tr("Flipped 180°"))
            return 6;
        if (label === I18n.tr("Flipped 270°"))
            return 7;
        return 0;
    }

    function getLogicalSize(output) {
        const mode = currentMode(output) || preferredMode(output);
        if (!mode)
            return { w: 1280, h: 720 };

        const scale = Math.max(0.25, output?.logical?.scale || 1);
        let width = mode.width / scale;
        let height = mode.height / scale;
        const transform = Number(output?.logical?.transform || 0);
        if ([1, 3, 5, 7].includes(transform)) {
            const swap = width;
            width = height;
            height = swap;
        }
        return {
            w: Math.round(width),
            h: Math.round(height)
        };
    }

    function estimatedPpi(outputName) {
        const output = allOutputs[outputName];
        const mode = currentMode(output) || preferredMode(output);
        if (!output || !mode || !(output.physicalWidth > 0) || !(output.physicalHeight > 0))
            return 0;
        const diagonalPixels = Math.sqrt(mode.width * mode.width + mode.height * mode.height);
        const widthInches = output.physicalWidth / 25.4;
        const heightInches = output.physicalHeight / 25.4;
        const diagonalInches = Math.sqrt(widthInches * widthInches + heightInches * heightInches);
        return diagonalInches > 0 ? Math.round(diagonalPixels / diagonalInches) : 0;
    }

    function setPendingChange(outputName, key, value) {
        const next = clone(pendingChanges || {});
        if (!next[outputName])
            next[outputName] = {};
        next[outputName][key] = value;
        pendingChanges = next;
    }

    function clearOutputPendingChange(outputName, key) {
        const next = clone(pendingChanges || {});
        if (!next[outputName])
            return;
        delete next[outputName][key];
        if (Object.keys(next[outputName]).length === 0)
            delete next[outputName];
        pendingChanges = next;
    }

    function getPendingValue(outputName, key) {
        return pendingChanges?.[outputName]?.[key];
    }

    function canDisableOutput(outputName) {
        let enabled = 0;
        for (const name of Object.keys(allOutputs || {})) {
            if (name !== outputName && allOutputs[name]?.enabled)
                enabled++;
        }
        return enabled > 0;
    }

    function buildHeads(usePending) {
        const heads = [];
        const changesMap = usePending ? pendingChanges : {};

        for (const raw of (WlrOutputService.outputs || [])) {
            const changes = changesMap?.[raw.name] || {};
            const enabled = changes.enabled !== undefined ? !!changes.enabled : raw.enabled !== false;
            const head = {
                name: raw.name,
                enabled
            };

            if (enabled) {
                const preferred = (raw.modes || []).find(mode => mode.preferred) || raw.modes?.[0] || null;
                const modeId = changes.modeId !== undefined
                    ? changes.modeId
                    : (raw.currentMode?.id ?? preferred?.id);
                if (modeId !== undefined)
                    head.modeId = modeId;

                const position = changes.position || {
                    x: raw.x ?? 0,
                    y: raw.y ?? 0
                };
                head.position = {
                    x: Math.round(position.x),
                    y: Math.round(position.y)
                };

                const scale = changes.scale !== undefined ? changes.scale : (raw.scale > 0 ? raw.scale : 1);
                head.scale = Math.max(0.25, Math.min(4, Number(scale) || 1));
                head.transform = changes.transform !== undefined ? changes.transform : (raw.transform ?? 0);

                if (raw.adaptiveSyncSupported)
                    head.adaptiveSync = (changes.vrr !== undefined ? changes.vrr : raw.adaptiveSync === 1) ? 1 : 0;
            }

            heads.push(head);
        }

        return heads;
    }

    function describeChanges() {
        const descriptions = [];
        for (const outputName of Object.keys(pendingChanges || {})) {
            const changes = pendingChanges[outputName];
            const displayName = getOutputDisplayName(allOutputs[outputName], outputName);
            if (changes.enabled !== undefined)
                descriptions.push(displayName + ": " + (changes.enabled ? I18n.tr("Enabled") : I18n.tr("Disabled")));
            if (changes.modeId !== undefined) {
                const mode = allOutputs[outputName]?.modes?.find(item => item.id === changes.modeId);
                descriptions.push(displayName + ": " + I18n.tr("Resolution & refresh") + " → " + formatMode(mode));
            }
            if (changes.position)
                descriptions.push(displayName + ": " + I18n.tr("Position") + " → " + changes.position.x + ", " + changes.position.y);
            if (changes.scale !== undefined)
                descriptions.push(displayName + ": " + I18n.tr("Scale") + " → " + formatScale(changes.scale));
            if (changes.transform !== undefined)
                descriptions.push(displayName + ": " + I18n.tr("Rotation") + " → " + getTransformLabel(changes.transform));
            if (changes.vrr !== undefined)
                descriptions.push(displayName + ": VRR → " + (changes.vrr ? I18n.tr("On") : I18n.tr("Off")));
        }
        return descriptions;
    }

    function snapshotConfiguration(heads) {
        const saved = {};
        for (const head of heads) {
            const raw = rawOutput(head.name);
            if (!raw)
                continue;

            const entry = {
                name: head.name,
                make: raw.make || "",
                model: raw.model || "",
                serialNumber: raw.serialNumber || "",
                enabled: !!head.enabled
            };

            if (head.enabled) {
                let mode = null;
                if (head.modeId !== undefined)
                    mode = (raw.modes || []).find(candidate => candidate.id === head.modeId) || null;
                if (!mode)
                    mode = raw.currentMode || (raw.modes || []).find(candidate => candidate.preferred) || raw.modes?.[0] || null;
                if (mode) {
                    entry.mode = {
                        width: mode.width,
                        height: mode.height,
                        refresh: mode.refresh
                    };
                }

                entry.position = clone(head.position || { x: raw.x ?? 0, y: raw.y ?? 0 });
                entry.scale = head.scale ?? (raw.scale > 0 ? raw.scale : 1);
                entry.transform = head.transform ?? raw.transform ?? 0;
                if (raw.adaptiveSyncSupported)
                    entry.adaptiveSync = head.adaptiveSync ?? raw.adaptiveSync ?? 0;
            }

            saved[head.name] = entry;
        }

        return {
            version: 1,
            outputs: saved
        };
    }

    function hasPendingChangesFor(outputNames) {
        const names = Array.isArray(outputNames) ? outputNames : [];
        return names.some(name => pendingChanges?.[name] !== undefined);
    }

    function clearPendingNames(outputNames) {
        const next = clone(pendingChanges || {});
        for (const name of (outputNames || []))
            delete next[name];
        pendingChanges = next;
    }

    function discardChangesFor(outputNames) {
        clearPendingNames(outputNames);
    }

    function discardChanges() {
        pendingChanges = ({});
    }

    function buildHeadsFor(outputNames) {
        const allowed = {};
        for (const name of (outputNames || []))
            allowed[name] = true;

        const heads = [];
        for (const raw of (WlrOutputService.outputs || [])) {
            const changes = allowed[raw.name] ? (pendingChanges?.[raw.name] || {}) : {};
            const enabled = changes.enabled !== undefined ? !!changes.enabled : raw.enabled !== false;
            const head = { name: raw.name, enabled };

            if (enabled) {
                const preferred = (raw.modes || []).find(mode => mode.preferred) || raw.modes?.[0] || null;
                const modeId = changes.modeId !== undefined
                    ? changes.modeId
                    : (raw.currentMode?.id ?? preferred?.id);
                if (modeId !== undefined)
                    head.modeId = modeId;

                const position = changes.position || { x: raw.x ?? 0, y: raw.y ?? 0 };
                head.position = { x: Math.round(position.x), y: Math.round(position.y) };
                head.scale = Math.max(0.25, Math.min(4, Number(
                    changes.scale !== undefined ? changes.scale : (raw.scale > 0 ? raw.scale : 1)
                ) || 1));
                head.transform = changes.transform !== undefined ? changes.transform : (raw.transform ?? 0);
                if (raw.adaptiveSyncSupported)
                    head.adaptiveSync = (changes.vrr !== undefined ? changes.vrr : raw.adaptiveSync === 1) ? 1 : 0;
            }

            heads.push(head);
        }
        return heads;
    }

    function describeChangesFor(outputNames) {
        const allowed = {};
        for (const name of (outputNames || []))
            allowed[name] = true;
        const saved = pendingChanges;
        const filtered = {};
        for (const name of Object.keys(saved || {})) {
            if (allowed[name])
                filtered[name] = saved[name];
        }
        pendingChanges = filtered;
        const descriptions = describeChanges();
        pendingChanges = saved;
        return descriptions;
    }

    function applyChangesFor(outputNames) {
        const names = (outputNames || []).filter(name => pendingChanges?.[name] !== undefined);
        if (!hasOutputBackend || names.length === 0 || applying)
            return;

        const heads = buildHeadsFor(names);
        if (!heads.some(head => head.enabled)) {
            applyFailed(I18n.tr("At least one display must remain enabled."));
            return;
        }

        originalHeads = buildHeads(false);
        appliedHeads = clone(heads);
        appliedSnapshot = snapshotConfiguration(heads);
        appliedOutputNames = names.slice();
        const descriptions = describeChangesFor(names);
        applying = true;

        WlrOutputService.testConfiguration(heads, (testSuccess, testMessage) => {
            if (!testSuccess) {
                applying = false;
                appliedHeads = [];
                appliedSnapshot = null;
                appliedOutputNames = [];
                applyFailed(testMessage || I18n.tr("The display configuration is not supported."));
                return;
            }

            WlrOutputService.applyConfiguration(heads, (success, message) => {
                applying = false;
                if (!success) {
                    appliedHeads = [];
                    appliedSnapshot = null;
                    appliedOutputNames = [];
                    applyFailed(message || I18n.tr("Failed to apply display configuration."));
                    return;
                }
                changesApplied(descriptions);
            });
        });
    }

    function applyChanges() {
        if (!hasOutputBackend || !hasPendingChanges || applying)
            return;

        const heads = buildHeads(true);
        if (!heads.some(head => head.enabled)) {
            applyFailed(I18n.tr("At least one display must remain enabled."));
            return;
        }

        originalHeads = buildHeads(false);
        appliedHeads = clone(heads);
        appliedSnapshot = snapshotConfiguration(heads);
        appliedOutputNames = Object.keys(pendingChanges || {});
        const descriptions = describeChanges();
        applying = true;

        WlrOutputService.testConfiguration(heads, (testSuccess, testMessage) => {
            if (!testSuccess) {
                applying = false;
                appliedHeads = [];
                appliedSnapshot = null;
                appliedOutputNames = [];
                applyFailed(testMessage || I18n.tr("The display configuration is not supported."));
                return;
            }

            WlrOutputService.applyConfiguration(heads, (success, message) => {
                applying = false;
                if (!success) {
                    appliedHeads = [];
                    appliedSnapshot = null;
                    appliedOutputNames = [];
                    applyFailed(message || I18n.tr("Failed to apply display configuration."));
                    return;
                }
                changesApplied(descriptions);
            });
        });
    }

    function confirmChanges() {
        if (appliedSnapshot) {
            SettingsData.set("labwcDisplayConfiguration", appliedSnapshot);
            SettingsData.saveSettings();
        }

        const primary = resolvePrimaryDisplayName();
        if (primary !== SettingsData.primaryDisplayName) {
            SettingsData.set("primaryDisplayName", primary);
            SettingsData.saveSettings();
        }

        clearPendingNames(appliedOutputNames);
        originalHeads = [];
        appliedHeads = [];
        appliedSnapshot = null;
        appliedOutputNames = [];
        WlrOutputService.requestState();
        changesConfirmed();
    }

    function revertChanges() {
        const restore = clone(originalHeads || []);
        clearPendingNames(appliedOutputNames);
        appliedHeads = [];
        appliedSnapshot = null;
        appliedOutputNames = [];
        originalHeads = [];

        if (restore.length === 0) {
            changesReverted();
            return;
        }

        WlrOutputService.applyConfiguration(restore, () => {
            WlrOutputService.requestState();
            changesReverted();
        });
    }

    function updatePosition(outputName, x, y) {
        setPendingChange(outputName, "position", {
            x: Math.round(x),
            y: Math.round(y)
        });
    }

    function checkOverlap(testName, testX, testY, testW, testH) {
        for (const name of Object.keys(allOutputs || {})) {
            if (name === testName || !allOutputs[name]?.enabled)
                continue;
            const other = allOutputs[name];
            const size = getLogicalSize(other);
            const ox = other.logical?.x ?? 0;
            const oy = other.logical?.y ?? 0;
            const overlap = testX < ox + size.w && testX + testW > ox
                    && testY < oy + size.h && testY + testH > oy;
            if (overlap)
                return true;
        }
        return false;
    }

    function snapToEdges(testName, posX, posY, testW, testH) {
        const threshold = 32;
        let bestX = posX;
        let bestY = posY;
        let bestDX = threshold + 1;
        let bestDY = threshold + 1;

        for (const name of Object.keys(allOutputs || {})) {
            if (name === testName || !allOutputs[name]?.enabled)
                continue;

            const other = allOutputs[name];
            const size = getLogicalSize(other);
            const ox = other.logical?.x ?? 0;
            const oy = other.logical?.y ?? 0;

            const xCandidates = [ox - testW, ox + size.w, ox, ox + size.w - testW];
            const yCandidates = [oy - testH, oy + size.h, oy, oy + size.h - testH];

            for (const candidate of xCandidates) {
                const distance = Math.abs(candidate - posX);
                if (distance < bestDX && distance <= threshold) {
                    bestDX = distance;
                    bestX = candidate;
                }
            }
            for (const candidate of yCandidates) {
                const distance = Math.abs(candidate - posY);
                if (distance < bestDY && distance <= threshold) {
                    bestDY = distance;
                    bestY = candidate;
                }
            }
        }

        return Qt.point(Math.round(bestX), Math.round(bestY));
    }
}
