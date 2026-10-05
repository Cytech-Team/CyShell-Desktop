.pragma library

const ACTION_TYPES = [
    { id: "cyshell", label: "CyShell Action", icon: "widgets" },
    { id: "compositor", label: "Compositor", icon: "desktop_windows" },
    { id: "spawn", label: "Run Command", icon: "terminal" },
    { id: "shell", label: "Shell Command", icon: "code" }
];

const CYSHELL_ACTIONS = [
    { id: "spawn cyshell ipc call spotlight toggle", label: "Default Launcher: Toggle" },
    { id: "spawn cyshell ipc call spotlight open", label: "Default Launcher: Open" },
    { id: "spawn cyshell ipc call spotlight close", label: "Default Launcher: Close" },
    { id: "spawn cyshell ipc call island toggle home", label: "CyIsland: Toggle" },
    { id: "spawn cyshell ipc call island open home", label: "CyIsland: Open Clock" },
    { id: "spawn cyshell ipc call island open media", label: "CyIsland: Open Media" },
    { id: "spawn cyshell ipc call island open launcher", label: "CyIsland: Open Launcher" },
    { id: "spawn cyshell ipc call island open controlcenter", label: "CyIsland: Open Control Center" },
    { id: "spawn cyshell ipc call island open wallpaper", label: "CyIsland: Open Wallpapers" },
    { id: "spawn cyshell ipc call island open weather", label: "CyIsland: Open Weather" },
    { id: "spawn cyshell ipc call island open notificationcenter", label: "CyIsland: Open Notification Center" },
    { id: "spawn cyshell ipc call island cycle", label: "CyIsland: Cycle Activity" },
    { id: "spawn cyshell ipc call island close", label: "CyIsland: Close" },
    { id: "spawn cyshell ipc call defaultApp browser", label: "Default Web Browser: Open" },
    { id: "spawn cyshell ipc call defaultApp fileManager", label: "Default File Manager: Open" },
    { id: "spawn cyshell ipc call defaultApp mail", label: "Default Mail: Open" },
    { id: "spawn cyshell ipc call defaultApp calendar", label: "Default Calendar: Open" },
    { id: "spawn cyshell ipc call defaultApp textEditor", label: "Default Text Editor: Open" },
    { id: "spawn cyshell ipc call defaultApp pdfReader", label: "Default PDF Reader: Open" },
    { id: "spawn cyshell ipc call defaultApp imageViewer", label: "Default Image Viewer: Open" },
    { id: "spawn cyshell ipc call defaultApp videoPlayer", label: "Default Video Player: Open" },
    { id: "spawn cyshell ipc call defaultApp musicPlayer", label: "Default Music Player: Open" },
    { id: "spawn cyshell ipc call spotlight-bar toggle", label: "Spotlight Bar: Toggle" },
    { id: "spawn cyshell ipc call spotlight-bar open", label: "Spotlight Bar: Open" },
    { id: "spawn cyshell ipc call spotlight-bar close", label: "Spotlight Bar: Close" },
    { id: "spawn cyshell ipc call clipboard toggle", label: "Clipboard: Toggle" },
    { id: "spawn cyshell ipc call clipboard open", label: "Clipboard: Open" },
    { id: "spawn cyshell ipc call clipboard close", label: "Clipboard: Close" },
    { id: "spawn cyshell ipc call notifications toggle", label: "Notifications: Toggle" },
    { id: "spawn cyshell ipc call notifications open", label: "Notifications: Open" },
    { id: "spawn cyshell ipc call notifications close", label: "Notifications: Close" },
    { id: "spawn cyshell ipc call processlist toggle", label: "Task Manager: Toggle" },
    { id: "spawn cyshell ipc call processlist open", label: "Task Manager: Open" },
    { id: "spawn cyshell ipc call processlist close", label: "Task Manager: Close" },
    { id: "spawn cyshell ipc call processlist focusOrToggle", label: "Task Manager: Focus or Toggle" },
    { id: "spawn cyshell ipc call settings toggle", label: "Settings: Toggle" },
    { id: "spawn cyshell ipc call settings open", label: "Settings: Open" },
    { id: "spawn cyshell ipc call settings close", label: "Settings: Close" },
    { id: "spawn cyshell ipc call settings focusOrToggle", label: "Settings: Focus or Toggle" },
    { id: "spawn cyshell agent open", label: "Agent: Open" },
    { id: "spawn cyshell agent review", label: "Agent: Review Permissions" },
    { id: "spawn cyshell agent stop", label: "Agent: Emergency Stop" },
    { id: "spawn cyshell ipc call powermenu toggle", label: "Power Menu: Toggle" },
    { id: "spawn cyshell ipc call powermenu open", label: "Power Menu: Open" },
    { id: "spawn cyshell ipc call powermenu close", label: "Power Menu: Close" },
    { id: "spawn cyshell ipc call control-center toggle", label: "Control Center: Toggle" },
    { id: "spawn cyshell ipc call control-center open", label: "Control Center: Open" },
    { id: "spawn cyshell ipc call control-center close", label: "Control Center: Close" },
    { id: "spawn cyshell ipc call notepad toggle", label: "Notepad: Toggle" },
    { id: "spawn cyshell ipc call notepad open", label: "Notepad: Open" },
    { id: "spawn cyshell ipc call notepad close", label: "Notepad: Close" },
    { id: "spawn cyshell ipc call notepad expand", label: "Notepad: Expand" },
    { id: "spawn cyshell ipc call notepad collapse", label: "Notepad: Collapse" },
    { id: "spawn cyshell ipc call notepad toggleExpand", label: "Notepad: Toggle Expand" },
    { id: "spawn cyshell ipc call dash toggle \"\"", label: "Dashboard: Toggle" },
    { id: "spawn cyshell ipc call dash open overview", label: "Dashboard: Overview" },
    { id: "spawn cyshell ipc call dash open media", label: "Dashboard: Media" },
    { id: "spawn cyshell ipc call dash open weather", label: "Dashboard: Weather" },
    { id: "spawn cyshell ipc call dankdash wallpaper", label: "Wallpaper Browser" },
    { id: "spawn cyshell ipc call file browse wallpaper", label: "File: Browse Wallpaper" },
    { id: "spawn cyshell ipc call file browse profile", label: "File: Browse Profile" },
    { id: "spawn cyshell ipc call color-picker toggle", label: "Color Picker: Toggle" },
    { id: "spawn cyshell ipc call color-picker open", label: "Color Picker: Open" },
    { id: "spawn cyshell ipc call color-picker close", label: "Color Picker: Close" },
    { id: "spawn cyshell ipc call keybinds toggle labwc", label: "Keybinds Cheatsheet: Toggle" },
    { id: "spawn cyshell ipc call keybinds open labwc", label: "Keybinds Cheatsheet: Open" },
    { id: "spawn cyshell ipc call keybinds close", label: "Keybinds Cheatsheet: Close" },
    { id: "spawn cyshell ipc call lock lock", label: "Lock Screen" },
    { id: "spawn cyshell ipc call lock lockAndOutputsOff", label: "Lock Screen & Outputs Off" },
    { id: "spawn cyshell ipc call lock demo", label: "Lock Screen: Demo" },
    { id: "spawn cyshell ipc call inhibit toggle", label: "Idle Inhibit: Toggle" },
    { id: "spawn cyshell ipc call inhibit enable", label: "Idle Inhibit: Enable" },
    { id: "spawn cyshell ipc call inhibit disable", label: "Idle Inhibit: Disable" },
    { id: "spawn cyshell ipc call audio increment 5", label: "Volume Up" },
    { id: "spawn cyshell ipc call audio increment 1", label: "Volume Up (1%)" },
    { id: "spawn cyshell ipc call audio increment 5", label: "Volume Up (5%)" },
    { id: "spawn cyshell ipc call audio increment 10", label: "Volume Up (10%)" },
    { id: "spawn cyshell ipc call audio decrement 5", label: "Volume Down" },
    { id: "spawn cyshell ipc call audio decrement 1", label: "Volume Down (1%)" },
    { id: "spawn cyshell ipc call audio decrement 5", label: "Volume Down (5%)" },
    { id: "spawn cyshell ipc call audio decrement 10", label: "Volume Down (10%)" },
    { id: "spawn cyshell ipc call mpris increment 5", label: "Player Volume Up (5%)" },
    { id: "spawn cyshell ipc call mpris decrement 5", label: "Player Volume Down (5%)" },
    { id: "spawn cyshell ipc call audio mute", label: "Volume Mute Toggle" },
    { id: "spawn cyshell ipc call mic mute", label: "Microphone Mute Toggle" },
    { id: "spawn cyshell ipc call audio cycleoutput", label: "Audio Output: Cycle" },
    { id: "spawn cyshell ipc call brightness increment 5 \"\"", label: "Brightness Up" },
    { id: "spawn cyshell ipc call brightness increment 1 \"\"", label: "Brightness Up (1%)" },
    { id: "spawn cyshell ipc call brightness increment 5 \"\"", label: "Brightness Up (5%)" },
    { id: "spawn cyshell ipc call brightness increment 10 \"\"", label: "Brightness Up (10%)" },
    { id: "spawn cyshell ipc call brightness decrement 5 \"\"", label: "Brightness Down" },
    { id: "spawn cyshell ipc call brightness decrement 1 \"\"", label: "Brightness Down (1%)" },
    { id: "spawn cyshell ipc call brightness decrement 5 \"\"", label: "Brightness Down (5%)" },
    { id: "spawn cyshell ipc call brightness decrement 10 \"\"", label: "Brightness Down (10%)" },
    { id: "spawn cyshell ipc call brightness toggleExponential \"\"", label: "Brightness: Toggle Exponential" },
    { id: "spawn cyshell ipc call theme toggle", label: "Theme: Toggle Light/Dark" },
    { id: "spawn cyshell ipc call theme light", label: "Theme: Light Mode" },
    { id: "spawn cyshell ipc call theme dark", label: "Theme: Dark Mode" },
    { id: "spawn cyshell ipc call night toggle", label: "Night Mode: Toggle" },
    { id: "spawn cyshell ipc call night enable", label: "Night Mode: Enable" },
    { id: "spawn cyshell ipc call night disable", label: "Night Mode: Disable" },
    { id: "spawn cyshell ipc call bar toggle index 0", label: "Bar: Toggle (Primary)" },
    { id: "spawn cyshell ipc call bar reveal index 0", label: "Bar: Reveal (Primary)" },
    { id: "spawn cyshell ipc call bar hide index 0", label: "Bar: Hide (Primary)" },
    { id: "spawn cyshell ipc call bar toggleReveal index 0", label: "Bar: Toggle Autohide Reveal (Primary)" },
    { id: "spawn cyshell ipc call bar toggleAutoHide index 0", label: "Bar: Toggle Auto-Hide (Primary)" },
    { id: "spawn cyshell ipc call bar autoHide index 0", label: "Bar: Enable Auto-Hide (Primary)" },
    { id: "spawn cyshell ipc call bar manualHide index 0", label: "Bar: Disable Auto-Hide (Primary)" },
    { id: "spawn cyshell ipc call dock toggle", label: "Dock: Toggle" },
    { id: "spawn cyshell ipc call dock reveal", label: "Dock: Reveal" },
    { id: "spawn cyshell ipc call dock hide", label: "Dock: Hide" },
    { id: "spawn cyshell ipc call dock toggleAutoHide", label: "Dock: Toggle Auto-Hide" },
    { id: "spawn cyshell ipc call dock autoHide", label: "Dock: Enable Auto-Hide" },
    { id: "spawn cyshell ipc call dock manualHide", label: "Dock: Disable Auto-Hide" },
    { id: "spawn cyshell ipc call mpris playPause", label: "Media: Play/Pause" },
    { id: "spawn cyshell ipc call mpris play", label: "Media: Play" },
    { id: "spawn cyshell ipc call mpris pause", label: "Media: Pause" },
    { id: "spawn cyshell ipc call mpris previous", label: "Media: Previous Track" },
    { id: "spawn cyshell ipc call mpris next", label: "Media: Next Track" },
    { id: "spawn cyshell ipc call mpris stop", label: "Media: Stop" },
    { id: "spawn cyshell screenshot", label: "Screenshot: Region" },
    { id: "spawn cyshell screenshot full", label: "Screenshot: Full Screen" },
    { id: "spawn cyshell screenshot all", label: "Screenshot: All Screens" },
    { id: "spawn cyshell screenshot window", label: "Screenshot: Window" },
    { id: "spawn cyshell ipc call wallpaper next", label: "Wallpaper: Next" },
    { id: "spawn cyshell ipc call wallpaper prev", label: "Wallpaper: Previous" },
    { id: "spawn cyshell ipc call workspace-rename open", label: "Workspace: Rename" }
];

const LABWC_ACTIONS = {
    "Window": [
        { id: "Close", label: "Close Window" },
        { id: "Iconify", label: "Minimize Window" },
        { id: "Raise", label: "Raise Window" },
        { id: "Lower", label: "Lower Window" },
        { id: "ToggleFullscreen", label: "Toggle Fullscreen" },
        { id: "ToggleMaximize", label: "Toggle Maximize" },
        { id: "ToggleAlwaysOnTop", label: "Toggle Always on Top" },
        { id: "ToggleAlwaysOnBottom", label: "Toggle Always on Bottom" },
        { id: "ToggleOmnipresent", label: "Toggle Sticky Window" },
        { id: "ToggleDecorations", label: "Toggle Decorations" },
        { id: "SetDecorations", label: "Set Decorations" },
        { id: "SnapToEdge", label: "Snap to Edge" },
        { id: "ToggleSnapToEdge", label: "Toggle Snap to Edge" },
        { id: "SnapToRegion", label: "Snap to Region" },
        { id: "ToggleSnapToRegion", label: "Toggle Snap to Region" },
        { id: "UnSnap", label: "Restore Snapped Window" },
        { id: "MoveToEdge", label: "Move to Edge" },
        { id: "Resize", label: "Interactive Resize" },
        { id: "GrowToEdge", label: "Grow to Edge" },
        { id: "ShrinkToEdge", label: "Shrink to Edge" },
        { id: "AutoPlace", label: "Auto-place Window" },
        { id: "FitToOutput", label: "Fit Window to Output" }
    ],
    "Workspace": [
        { id: "GoToDesktop", label: "Switch Workspace" },
        { id: "SendToDesktop", label: "Move Window to Workspace" }
    ],
    "Monitor": [
        { id: "FocusOutput", label: "Focus Output" },
        { id: "MoveToOutput", label: "Move Window to Output" }
    ],
    "Alt-Tab": [
        { id: "NextWindow", label: "Next Window" },
        { id: "PreviousWindow", label: "Previous Window" },
        { id: "NextWindowImmediate", label: "Next Window (Immediate)" },
        { id: "PreviousWindowImmediate", label: "Previous Window (Immediate)" }
    ],
    "System": [
        { id: "ToggleShowDesktop", label: "Show Desktop" },
        { id: "ShowMenu", label: "Show Menu" },
        { id: "ToggleKeybinds", label: "Toggle Shortcut Inhibition" },
        { id: "ToggleMagnify", label: "Toggle Magnifier" },
        { id: "ZoomIn", label: "Magnifier Zoom In" },
        { id: "ZoomOut", label: "Magnifier Zoom Out" },
        { id: "Reconfigure", label: "Reload Labwc Configuration" },
        { id: "Exit", label: "Exit Labwc" }
    ]
};

const COMPOSITOR_ACTIONS = {
    labwc: LABWC_ACTIONS
};

const CATEGORY_ORDER = ["CyShell", "Execute", "Workspace", "Tags", "Window", "Move/Resize", "Focus", "Move", "Layout", "Groups", "Monitor", "Scratchpad", "Screenshot", "System", "Pass-through", "Overview", "Alt-Tab", "Other"];

const LABWC_ACTION_ARGS = {
    "ToggleMaximize": { args: [{ name: "value", type: "text", label: "Direction", placeholder: "both, horizontal, vertical" }] },
    "SetDecorations": { args: [{ name: "value", type: "text", label: "Decorations", placeholder: "full, border, none" }] },
    "SnapToEdge": { args: [{ name: "value", type: "text", label: "Direction", placeholder: "left, right, up, down, up-left..." }] },
    "ToggleSnapToEdge": { args: [{ name: "value", type: "text", label: "Direction", placeholder: "left, right, up, down, up-left..." }] },
    "SnapToRegion": { args: [{ name: "value", type: "text", label: "Region", placeholder: "region name" }] },
    "ToggleSnapToRegion": { args: [{ name: "value", type: "text", label: "Region", placeholder: "region name" }] },
    "MoveToEdge": { args: [{ name: "value", type: "text", label: "Direction", placeholder: "left, right, up, down" }] },
    "Resize": { args: [{ name: "value", type: "text", label: "Direction", placeholder: "left, right, up, down, up-left..." }] },
    "GrowToEdge": { args: [{ name: "value", type: "text", label: "Direction", placeholder: "left, right, up, down" }] },
    "ShrinkToEdge": { args: [{ name: "value", type: "text", label: "Direction", placeholder: "left, right, up, down" }] },
    "AutoPlace": { args: [{ name: "value", type: "text", label: "Policy", placeholder: "automatic, cursor, center, cascade" }] },
    "GoToDesktop": { args: [{ name: "value", type: "text", label: "Workspace", placeholder: "1, left, right, last, workspace name" }] },
    "SendToDesktop": { args: [{ name: "value", type: "text", label: "Workspace", placeholder: "1, left, right, last, workspace name" }] },
    "FocusOutput": { args: [{ name: "value", type: "text", label: "Output", placeholder: "left, right, up, down, HDMI-A-1" }] },
    "MoveToOutput": { args: [{ name: "value", type: "text", label: "Output", placeholder: "left, right, up, down, HDMI-A-1" }] },
    "ShowMenu": { args: [{ name: "value", type: "text", label: "Menu", placeholder: "root-menu, client-menu" }] }
};

const ACTION_ARGS = {
    labwc: LABWC_ACTION_ARGS
};

const SCREENSHOT_FLAGS = [
    { name: "no-file", type: "flag", flag: "--no-file", label: "Save", inverted: true },
    { name: "no-clipboard", type: "flag", flag: "--no-clipboard", label: "Clipboard", inverted: true },
    { name: "cursor", type: "flag", flag: "--cursor=on", label: "Pointer" }
];

const CYSHELL_ACTION_ARGS = {
    "audio increment": {
        base: "spawn cyshell ipc call audio increment",
        args: [{ name: "amount", type: "number", label: "Amount %", placeholder: "5", default: "5" }]
    },
    "audio decrement": {
        base: "spawn cyshell ipc call audio decrement",
        args: [{ name: "amount", type: "number", label: "Amount %", placeholder: "5", default: "5" }]
    },
    "player increment": {
        base: "spawn cyshell ipc call mpris increment",
        args: [{ name: "amount", type: "number", label: "Amount %", placeholder: "5", default: "5" }]
    },
    "player decrement": {
        base: "spawn cyshell ipc call mpris decrement",
        args: [{ name: "amount", type: "number", label: "Amount %", placeholder: "5", default: "5" }]
    },
    "brightness increment": {
        base: "spawn cyshell ipc call brightness increment",
        args: [
            { name: "amount", type: "number", label: "Amount %", placeholder: "5", default: "5" },
            { name: "device", type: "text", label: "Device", placeholder: "leave empty for default", default: "" }
        ]
    },
    "brightness decrement": {
        base: "spawn cyshell ipc call brightness decrement",
        args: [
            { name: "amount", type: "number", label: "Amount %", placeholder: "5", default: "5" },
            { name: "device", type: "text", label: "Device", placeholder: "leave empty for default", default: "" }
        ]
    },
    "brightness toggleExponential": {
        base: "spawn cyshell ipc call brightness toggleExponential",
        args: [
            { name: "device", type: "text", label: "Device", placeholder: "leave empty for default", default: "" }
        ]
    },
    "dash toggle": {
        base: "spawn cyshell ipc call dash toggle",
        args: [
            { name: "tab", type: "text", label: "Tab", placeholder: "overview, media, wallpaper, weather", default: "" }
        ]
    },
    "screenshot": { base: "spawn cyshell screenshot", args: SCREENSHOT_FLAGS },
    "screenshot full": { base: "spawn cyshell screenshot full", args: SCREENSHOT_FLAGS },
    "screenshot all": { base: "spawn cyshell screenshot all", args: SCREENSHOT_FLAGS },
    "screenshot window": { base: "spawn cyshell screenshot window", args: SCREENSHOT_FLAGS }
};

const CYSHELL_AMOUNT_LABELS = {
    "audio increment": "Volume Up",
    "audio decrement": "Volume Down",
    "mpris increment": "Player Volume Up",
    "mpris decrement": "Player Volume Down",
    "brightness increment": "Brightness Up",
    "brightness decrement": "Brightness Down"
};

function getCyShellAmountLabel(action) {
    var parsed = parseCyShellActionArgs(action);
    var label = CYSHELL_AMOUNT_LABELS[parsed.base];
    if (!label)
        return null;
    var amount = parsed.args?.amount;
    if (amount === undefined || amount === null || amount === "")
        return label;
    return label + " (" + amount + "%)";
}

function getActionTypes() {
    return ACTION_TYPES;
}

function getCyShellActionArgs() {
    return CYSHELL_ACTION_ARGS;
}


function getCyShellActions() {
    return CYSHELL_ACTIONS;
}

function getCompositorCategories(compositor) {
    return Object.keys(LABWC_ACTIONS);
}

function getCompositorActions(compositor, category) {
    return LABWC_ACTIONS[category] || [];
}
function getCategoryOrder() {
    return CATEGORY_ORDER;
}

function canonicalizeCyShellAction(action) {
    if (!action)
        return "";
    var value = String(action).trim();
    return value.replace(/^spawn\s+(?:\/usr\/local\/bin\/cyshell|\/usr\/bin\/cyshell|cyshell)(?=\s|$)/, "spawn cyshell");
}

function actionsEquivalent(first, second) {
    return canonicalizeCyShellAction(first) === canonicalizeCyShellAction(second);
}

function findCyShellAction(actionId) {
    for (let i = 0; i < CYSHELL_ACTIONS.length; i++) {
        if (actionsEquivalent(CYSHELL_ACTIONS[i].id, actionId))
            return CYSHELL_ACTIONS[i];
    }
    return null;
}


function findCompositorAction(compositor, actionId) {
    for (const cat in LABWC_ACTIONS) {
        const acts = LABWC_ACTIONS[cat];
        for (let i = 0; i < acts.length; i++) {
            if (acts[i].id === actionId)
                return acts[i];
        }
    }
    return null;
}
function getActionLabel(action, compositor) {
    if (!action)
        return "";

    var amountLabel = getCyShellAmountLabel(action);
    if (amountLabel)
        return amountLabel;

    var cyShellAct = findCyShellAction(action);
    if (cyShellAct)
        return cyShellAct.label;

    var cyShellKey = findCyShellArgKey(action);
    var baseAct = cyShellKey ? findCyShellAction(CYSHELL_ACTION_ARGS[cyShellKey].base) : null;
    if (baseAct)
        return baseAct.label;

    if (compositor) {
        var compAct = findCompositorAction(compositor, action);
        if (compAct)
            return compAct.label;
        var base = action.split(" ")[0];
        compAct = findCompositorAction(compositor, base);
        if (compAct)
            return compAct.label;
    }

    if (action.startsWith("spawn sh -c "))
        return action.slice(12).replace(/^["']|["']$/g, "");
    if (action.startsWith("spawn "))
        return action.slice(6);
    return action;
}

function getActionType(action) {
    if (!action)
        return "compositor";
    if (isCyShellAction(action))
        return "cyshell";
    if (/^spawn \w+ -c /.test(action) || action.startsWith("spawn_shell "))
        return "shell";
    if (action.startsWith("spawn "))
        return "spawn";
    return "compositor";
}

function isCyShellAction(action) {
    if (!action)
        return false;
    const canonical = canonicalizeCyShellAction(action);
    return canonical.startsWith("spawn cyshell ipc call ") || /^spawn cyshell screenshot( |$)/.test(canonical) || /^spawn cyshell agent( |$)/.test(canonical);
}

function isValidAction(action) {
    if (!action)
        return false;
    switch (action) {
        case "spawn":
        case "spawn ":
        case "spawn sh -c \"\"":
        case "spawn sh -c ''":
        case "spawn_shell":
        case "spawn_shell ":
            return false;
    }
    return true;
}


function isKnownCompositorAction(compositor, action) {
    if (!action)
        return false;
    var found = findCompositorAction("labwc", action);
    if (found)
        return true;
    var base = action.split(" ")[0];
    return findCompositorAction("labwc", base) !== null;
}
function buildSpawnAction(command, args) {
    if (!command)
        return "";
    let parts = [command];
    if (args && args.length > 0)
        parts = parts.concat(args.filter(function (a) { return a; }));
    return "spawn " + parts.join(" ");
}


function buildShellAction(compositor, shellCmd, shell) {
    if (!shellCmd)
        return "";
    var shellBin = shell || "sh";
    return "spawn " + shellBin + " -c \"" + shellCmd.replace(/"/g, "\\\"") + "\"";
}
function parseSpawnCommand(action) {
    if (!action || !action.startsWith("spawn "))
        return { command: "", args: [] };
    const rest = action.slice(6);
    const parts = rest.split(" ").filter(function (p) { return p; });
    return {
        command: parts[0] || "",
        args: parts.slice(1)
    };
}

function parseShellCommand(action) {
    if (!action)
        return "";
    var match = action.match(/^spawn (\w+) -c (.+)$/);
    if (match) {
        var content = match[2];
        if ((content.startsWith('"') && content.endsWith('"')) || (content.startsWith("'") && content.endsWith("'")))
            content = content.slice(1, -1);
        return content.replace(/\\"/g, "\"");
    }
    if (action.startsWith("spawn_shell "))
        return action.slice(12);
    return "";
}

function getShellFromAction(action) {
    if (!action)
        return "sh";
    var match = action.match(/^spawn (\w+) -c /);
    return match ? match[1] : "sh";
}


function getActionArgConfig(compositor, action) {
    if (!action)
        return null;

    var baseAction = action.split(" ")[0];
    if (LABWC_ACTION_ARGS[baseAction])
        return { type: "compositor", base: baseAction, config: LABWC_ACTION_ARGS[baseAction] };

    var cyShellKey = findCyShellArgKey(action);
    if (cyShellKey)
        return { type: "cyshell", base: cyShellKey, config: CYSHELL_ACTION_ARGS[cyShellKey] };

    return null;
}
function findCyShellArgKey(action) {
    action = canonicalizeCyShellAction(action);
    var best = null;
    for (var key in CYSHELL_ACTION_ARGS) {
        var base = CYSHELL_ACTION_ARGS[key].base;
        if (action !== base && !action.startsWith(base + " "))
            continue;
        if (!best || base.length > CYSHELL_ACTION_ARGS[best].base.length)
            best = key;
    }
    return best;
}


function parseCompositorActionArgs(compositor, action) {
    if (!action)
        return { base: "", args: {} };

    var parts = action.split(" ");
    var base = parts[0];
    if (!LABWC_ACTION_ARGS[base])
        return { base: action, args: {} };

    var value = parts.slice(1).join(" ");
    return {
        base: base,
        args: value ? { value: value } : {}
    };
}

function buildCompositorAction(compositor, base, args) {
    if (!base)
        return "";
    if (!args || Object.keys(args).length === 0)
        return base;
    var value = args.value;
    return value === undefined || value === null || value === "" ? base : base + " " + value;
}
function parseCyShellActionArgs(action) {
    if (!action)
        return { base: "", args: {} };

    action = canonicalizeCyShellAction(action);
    var key = findCyShellArgKey(action);
    if (!key)
        return { base: action, args: {} };

    var config = CYSHELL_ACTION_ARGS[key];
    var rest = action.slice(config.base.length).trim();
    var result = { base: key, args: {} };

    if (!rest)
        return result;

    var tokens = [];
    var current = "";
    var inQuotes = false;
    var hadQuotes = false;
    for (var i = 0; i < rest.length; i++) {
        var c = rest[i];
        switch (c) {
            case '"':
                inQuotes = !inQuotes;
                hadQuotes = true;
                break;
            case ' ':
                if (inQuotes) {
                    current += c;
                } else if (current || hadQuotes) {
                    tokens.push(current);
                    current = "";
                    hadQuotes = false;
                }
                break;
            default:
                current += c;
                break;
        }
    }
    if (current || hadQuotes)
        tokens.push(current);

    var positional = tokens.filter(t => !t.startsWith("--"));
    var p = 0;
    for (var j = 0; j < config.args.length; j++) {
        var argDef = config.args[j];
        if (argDef.type === "flag") {
            result.args[argDef.name] = tokens.indexOf(argDef.flag) !== -1;
            continue;
        }
        if (p >= positional.length)
            break;
        result.args[argDef.name] = positional[p++];
    }

    return result;
}

function buildCyShellAction(baseKey, args) {
    var config = CYSHELL_ACTION_ARGS[baseKey];
    if (!config)
        return "";

    var parts = [config.base];
    var positional = config.args.filter(a => a.type !== "flag");
    var flags = config.args.filter(a => a.type === "flag");

    for (var i = 0; i < positional.length; i++) {
        var argDef = positional[i];
        var value = args?.[argDef.name];
        if (value === undefined || value === null)
            value = argDef.default ?? "";

        if (argDef.type === "text" && value === "") {
            parts.push('""');
        } else if (value !== "") {
            parts.push(value);
        } else {
            break;
        }
    }

    for (var f = 0; f < flags.length; f++) {
        if (args?.[flags[f].name] === true)
            parts.push(flags[f].flag);
    }

    return parts.join(" ");
}
