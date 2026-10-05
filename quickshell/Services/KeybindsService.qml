pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "../Common/KeybindActions.js" as Actions

Singleton {
    id: root
    readonly property var log: Log.scoped("KeybindsService")

    readonly property bool available: true
    readonly property string currentProvider: "labwc"
    readonly property string cheatsheetProvider: "labwc"
    readonly property bool cheatsheetAvailable: true
    property bool cheatsheetLoading: false
    property var cheatsheet: ({})

    property bool loading: false
    property bool saving: false
    property bool resetAllBusy: false
    property string lastError: ""
    property string modKey: "Super"
    property var _rawData: null
    property var keybinds: ({})
    property var _allBinds: ({})
    property var _categories: []
    property var _flatCache: []
    property var displayList: []
    property int _dataVersion: 0
    property int managedOverrideCount: 0
    property string _pendingSavedKey: ""
    readonly property bool requiresBindReview: false
    readonly property string bindEditSession: "labwc"
    readonly property bool bindMutationBusy: saving || removeProcess.running || resetAllProcess.running

    readonly property var categoryOrder: Actions.getCategoryOrder()
    readonly property bool readOnly: false
    readonly property var actionTypes: Actions.getActionTypes()
    readonly property var cyShellActions: getCyShellActions()

    signal bindsLoaded
    signal bindSaved(string key)
    signal bindSaveCompleted(bool success)
    signal bindRemoved(string key)
    signal cheatsheetLoaded

    Process {
        id: cheatsheetProcess
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.cheatsheet = JSON.parse(text);
                } catch (e) {
                    log.error("Failed to parse cheatsheet:", e);
                    root.cheatsheet = {};
                }
                root.cheatsheetLoading = false;
                root.cheatsheetLoaded();
            }
        }

        onExited: exitCode => {
            if (exitCode === 0)
                return;
            log.warn("Cheatsheet load failed with code:", exitCode);
            root.cheatsheetLoading = false;
        }
    }

    Process {
        id: loadProcess
        running: false
        property string provider: ""

        stdout: StdioCollector {
            onStreamFinished: {
                if (loadProcess.provider !== root.currentProvider)
                    return;
                try {
                    root._rawData = JSON.parse(text);
                    root._processData();
                } catch (e) {
                    log.error("Failed to parse binds:", e);
                }
                root.loading = false;
            }
        }

        onExited: exitCode => {
            if (provider !== root.currentProvider)
                return;
            if (exitCode !== 0) {
                log.warn("Load process failed with code:", exitCode);
                root.loading = false;
            }
        }
    }

    Process {
        id: saveProcess
        running: false
        property string savedKey: ""
        property string provider: ""

        stderr: StdioCollector {
            onStreamFinished: {
                if (saveProcess.provider !== root.currentProvider)
                    return;
                if (!text.trim())
                    return;
                root.lastError = text.trim();
                ToastService.showError(I18n.tr("Failed to save keybind"), "", root.lastError, "keybinds");
            }
        }

        onExited: exitCode => {
            root.saving = false;
            if (provider !== root.currentProvider) {
                savedKey = "";
                return;
            }
            if (exitCode !== 0) {
                root._pendingSavedKey = "";
                savedKey = "";
                log.error("Save failed with code:", exitCode);
                root.bindSaveCompleted(false);
                return;
            }
            root.lastError = "";
            root._pendingSavedKey = savedKey;
            savedKey = "";
            root.bindSaveCompleted(true);
            LabwcService.reconfigure();
            root.loadBinds(false);
        }
    }

    Process {
        id: removeProcess
        running: false
        property string provider: ""

        stderr: StdioCollector {
            onStreamFinished: {
                if (removeProcess.provider !== root.currentProvider)
                    return;
                if (!text.trim())
                    return;
                root.lastError = text.trim();
                ToastService.showError(I18n.tr("Failed to remove keybind"), "", root.lastError, "keybinds");
            }
        }

        onExited: exitCode => {
            if (provider !== root.currentProvider)
                return;
            if (exitCode !== 0) {
                log.error("Remove failed with code:", exitCode);
                return;
            }
            root.lastError = "";
            LabwcService.reconfigure();
            root.loadBinds(false);
        }
    }

    Process {
        id: resetAllProcess
        running: false
        property string provider: ""
        property string outputText: ""
        property string errorText: ""

        stdout: StdioCollector {
            onStreamFinished: resetAllProcess.outputText = text.trim();
        }

        stderr: StdioCollector {
            onStreamFinished: resetAllProcess.errorText = text.trim();
        }

        onExited: exitCode => {
            root.resetAllBusy = false;
            if (provider !== root.currentProvider)
                return;

            let result = null;
            try {
                result = JSON.parse(outputText);
            } catch (e) {
                result = null;
            }
            if (exitCode !== 0 || !result?.success) {
                const message = result?.message || errorText || I18n.tr("The keybind reset did not complete.");
                root.lastError = message;
                ToastService.showError(I18n.tr("Failed to reset keybinds"), "", message, "keybinds");
                return;
            }

            const resetCount = Math.max(0, Number(result.reset) || 0);
            root.lastError = "";
            if (resetCount === 0) {
                ToastService.showInfo(I18n.tr("There are no CyShell keybind overrides to reset."));
                return;
            }
            LabwcService.reconfigure();
            root.loadBinds(false);
            ToastService.showInfo(I18n.tr("Reset %1 CyShell keybind overrides.", "keybind reset success, %1 is the number of overrides removed").arg(resetCount));
        }
    }

    function forceReload() {
        _allBinds = {};
        _flatCache = [];
        _categories = [];
        loadBinds(true);
    }

    function loadCheatsheet(provider) {
        if (cheatsheetProcess.running)
            return;
        cheatsheetLoading = true;
        cheatsheetProcess.command = [Proc.cyshellBin, "keybinds", "show", "labwc"];
        cheatsheetProcess.running = true;
    }

    function loadBinds(showLoading) {
        if (loadProcess.running || !available)
            return;
        const hasData = Object.keys(_allBinds).length > 0;
        loading = showLoading !== false && !hasData;
        loadProcess.command = [Proc.cyshellBin, "keybinds", "show", currentProvider];
        loadProcess.provider = currentProvider;
        loadProcess.running = true;
    }

    function _processData() {
        keybinds = _rawData || {};
        modKey = "Super";
        if (!_rawData?.binds) {
            _allBinds = {};
            _categories = [];
            _flatCache = [];
            displayList = [];
            managedOverrideCount = Number(_rawData?.managedOverrideCount) || 0;
            _dataVersion++;
            bindsLoaded();
            if (_pendingSavedKey) {
                bindSaved(_pendingSavedKey);
                _pendingSavedKey = "";
            }
            return;
        }

        const processed = {};
        const bindsData = _rawData.binds;
        for (const cat in bindsData) {
            const binds = bindsData[cat];
            for (var i = 0; i < binds.length; i++) {
                const bind = binds[i];
                const targetCat = Actions.isCyShellAction(bind.action) ? "CyShell" : cat;
                if (!processed[targetCat])
                    processed[targetCat] = [];
                processed[targetCat].push(bind);
            }
        }

        const sortedCats = Object.keys(processed).sort((a, b) => {
            const ai = categoryOrder.indexOf(a);
            const bi = categoryOrder.indexOf(b);
            return (ai === -1 ? 999 : ai) - (bi === -1 ? 999 : bi);
        });

        const grouped = [];
        const actionMap = {};
        let overrideCount = 0;
        for (var ci = 0; ci < sortedCats.length; ci++) {
            const category = sortedCats[ci];
            const binds = processed[category];
            if (!binds)
                continue;
            for (var i = 0; i < binds.length; i++) {
                const bind = binds[i];
                const action = bind.action || "";
                const sourceStr = bind.source || "config";
                if (sourceStr === "cyshell")
                    overrideCount++;
                const keyData = {
                    "key": bind.key || "",
                    "desc": bind.desc || "",
                    "source": sourceStr,
                    "isOverride": sourceStr === "cyshell",
                    "isCyShellManaged": sourceStr === "cyshell" || sourceStr === "cyshell-default",
                    "hasDefault": bind.hasDefault === true,
                    "cooldownMs": bind.cooldownMs || 0,
                    "flags": bind.flags || "",
                    "allowWhenLocked": bind.allowWhenLocked || false,
                    "allowInhibiting": bind.allowInhibiting,
                    "repeat": bind.repeat
                };
                if (actionMap[action]) {
                    actionMap[action].keys.push(keyData);
                    if (!actionMap[action].desc && bind.desc)
                        actionMap[action].desc = bind.desc;
                    if (!actionMap[action].conflict && bind.conflict)
                        actionMap[action].conflict = bind.conflict;
                } else {
                    const entry = {
                        "category": category,
                        "action": action,
                        "desc": bind.desc || "",
                        "keys": [keyData],
                        "conflict": bind.conflict || null
                    };
                    actionMap[action] = entry;
                    grouped.push(entry);
                }
            }
        }

        const list = [];
        for (const cat of sortedCats) {
            list.push({
                "id": "cat:" + cat,
                "type": "category",
                "name": cat
            });
            const binds = processed[cat];
            if (!binds)
                continue;
            for (const bind of binds)
                list.push({
                    "id": "bind:" + bind.key,
                    "type": "bind",
                    "key": bind.key,
                    "desc": bind.desc
                });
        }

        _allBinds = processed;
        _categories = sortedCats;
        _flatCache = grouped;
        displayList = list;
        managedOverrideCount = Number(_rawData.managedOverrideCount) || overrideCount;
        _dataVersion++;
        bindsLoaded();
        if (_pendingSavedKey) {
            bindSaved(_pendingSavedKey);
            _pendingSavedKey = "";
        }
    }

    function getCategories() {
        return _categories;
    }

    function getFlatBinds() {
        return _flatCache;
    }

    function keysForAction(actionId) {
        if (!actionId)
            return [];
        for (let i = 0; i < _flatCache.length; i++) {
            const group = _flatCache[i];
            if (!group || !Actions.actionsEquivalent(group.action, actionId) || !Array.isArray(group.keys))
                continue;
            const keys = [];
            for (let k = 0; k < group.keys.length; k++) {
                const key = group.keys[k]?.key || "";
                if (key)
                    keys.push(key);
            }
            return keys;
        }
        return [];
    }

    function captureBindEdit(binding, key) {
        return null;
    }

    function updateBindEdit(draft, key, data, operation) {
        return draft;
    }

    function loadBindReview(callback) {
        if (callback)
            callback(null, "");
    }

    function reconcileBindEdit(draft, snapshot) {
        return { draft: draft };
    }

    function bindEditError(code) {
        return I18n.tr("Keybind review is unavailable in Labwc mode.");
    }

    function describeBindReview(draft, current) {
        return "";
    }

    function saveBind(originalKey, bindData, draft, callback) {
        if (!bindData.key || !Actions.isValidAction(bindData.action))
            return;
        saving = true;
        const cmd = [Proc.cyshellBin, "keybinds", "set", currentProvider, bindData.key, bindData.action];
        cmd.push("--desc", bindData.desc || "");
        if (originalKey && originalKey !== bindData.key)
            cmd.push("--replace-key", originalKey);
        if (bindData.cooldownMs > 0)
            cmd.push("--cooldown-ms", String(bindData.cooldownMs));
        if (bindData.allowWhenLocked)
            cmd.push("--allow-when-locked");
        if (bindData.repeat === false)
            cmd.push("--no-repeat");
        if (bindData.allowInhibiting === false)
            cmd.push("--no-inhibiting");
        if (bindData.flags)
            cmd.push("--flags", bindData.flags);
        saveProcess.command = cmd;
        saveProcess.provider = currentProvider;
        saveProcess.savedKey = bindData.key;
        saveProcess.running = true;
    }

    function removeBind(key, draft, callback) {
        if (!key)
            return;
        removeProcess.command = [Proc.cyshellBin, "keybinds", "remove", currentProvider, key];
        removeProcess.provider = currentProvider;
        removeProcess.running = true;
        bindRemoved(key);
    }

    function resetBind(key, draft, callback) {
        if (!key)
            return;
        removeProcess.command = [Proc.cyshellBin, "keybinds", "reset", currentProvider, key];
        removeProcess.provider = currentProvider;
        removeProcess.running = true;
        bindRemoved(key);
    }

    function resetAllBinds() {
        if (currentProvider !== "labwc" || bindMutationBusy)
            return;
        resetAllBusy = true;
        lastError = "";
        resetAllProcess.provider = currentProvider;
        resetAllProcess.outputText = "";
        resetAllProcess.errorText = "";
        resetAllProcess.command = [Proc.cyshellBin, "keybinds", "reset-all", currentProvider, "--json"];
        resetAllProcess.running = true;
    }

    function getActionLabel(action) {
        return Actions.getActionLabel(action, "labwc");
    }

    function isKnownCompositorAction(action) {
        return Actions.isKnownCompositorAction("labwc", action);
    }

    function getCompositorCategories() {
        return Actions.getCompositorCategories("labwc");
    }

    function getCompositorActions(category) {
        return Actions.getCompositorActions("labwc", category);
    }

    function getCyShellActions() {
        return Actions.getCyShellActions(false, false);
    }
}
