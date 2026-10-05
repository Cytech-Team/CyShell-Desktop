#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

const root = path.resolve(import.meta.dirname, "..");
const files = {
  greeter: path.join(root, "quickshell/Modals/Greeter/GreeterCompletePage.qml"),
  service: path.join(root, "quickshell/Services/KeybindsService.qml"),
  tab: path.join(root, "quickshell/Modules/Settings/KeybindsTab.qml"),
  item: path.join(root, "quickshell/Modules/Settings/KeybindItem.qml"),
  actions: path.join(root, "quickshell/Common/KeybindActions.js"),
};

function read(file) {
  return fs.readFileSync(file, "utf8");
}

function fail(message) {
  console.error("VERIFY FAILED:", message);
  process.exit(1);
}

function assert(condition, message) {
  if (!condition)
    fail(message);
}

function featureFor(action) {
  const value = String(action || "");
  const featureNames = {
    "control-center": "Control Center",
    clipboard: "Clipboard",
    processlist: "Task Manager",
    settings: "Settings",
    notifications: "Notifications",
    lock: "Lock Screen",
  };
  if (value.includes("cyshell-cystart-toggle"))
    return "App Launcher";
  if (/\bcyshell\s+agent\s+open\b/.test(value))
    return "CyShell Agent";
  if (/\bcyshell\s+agent\s+stop\b/.test(value))
    return "Stop Agent Control";
  if (value.includes("cyshell-bar-rescue"))
    return "Rescue CyBar";
  if (/(?:^|\s)qterminal(?:\s|$)/.test(value))
    return "Terminal";
  const match = value.match(/\bcyshell\s+ipc\s+call\s+([\w-]+)/);
  return match ? (featureNames[match[1]] || null) : null;
}

function verifySource() {
  const source = Object.fromEntries(Object.entries(files).map(([name, file]) => [name, read(file)]));
  const banned = /\b(?:niri|hyprland|mangowc|mango|aqueous|dms)\b/i;
  for (const [name, text] of Object.entries(source)) {
    const match = text.match(banned);
    assert(!match, `${name} still contains inherited provider/DMS token: ${match?.[0]}`);
  }

  assert(source.service.includes('readonly property string currentProvider: "labwc"'), "KeybindsService is not pinned to Labwc");
  assert(source.service.includes('readonly property string cheatsheetProvider: "labwc"'), "cheatsheet provider is not pinned to Labwc");
  assert(!/CompositorService\./.test(source.service), "KeybindsService still branches on compositor runtime");
  assert(source.actions.includes("const LABWC_ACTIONS ="), "Labwc action table missing");
  assert(source.actions.includes("labwc: LABWC_ACTIONS"), "Labwc action registry missing");
  assert(!/const\s+(?:NIRI|HYPRLAND|MANGOWC)_/.test(source.actions), "alternate compositor action table remains");
  assert(source.actions.includes("function isCyShellAction"), "CyShell action classifier missing");
  assert(!source.actions.includes("isDmsAction"), "legacy DMS action classifier remains");
  assert(source.item.includes("KeybindsService.cyShellActions"), "KeybindItem is not using CyShell actions");
  assert(!source.item.includes("KeybindsService.dmsActions"), "legacy dmsActions reference remains");
  assert(source.tab.includes("labwc/rc.xml (existing shortcuts + CyShell overrides)"), "Labwc keybind target hint missing");
  assert(source.greeter.includes('"control-center": "Control Center"'), "control-center mapping missing");
  assert(source.greeter.includes("([\\w-]+)"), "hyphen-capable IPC feature parser missing");
  assert(source.greeter.includes("displayKeyParts"), "key display normalization missing");
  assert(source.greeter.includes("contentY = 0"), "Welcome page scroll reset missing");

  const js = source.actions.replace(/^\.pragma\s+library\s*\n/, "");
  try {
    new Function(js);
  } catch (error) {
    fail("KeybindActions.js syntax error: " + error.message);
  }

  console.log("LABWC SOURCE VERIFY PASSED");
}

function verifyLive() {
  let parsed;
  try {
    parsed = JSON.parse(execFileSync("cyshell", ["keybinds", "show", "labwc"], { encoding: "utf8" }));
  } catch (error) {
    fail("cannot read live Labwc keybinds: " + String(error.stderr || error.message));
  }
  assert(parsed?.provider === "labwc", "live provider is not labwc");
  assert(parsed?.binds && typeof parsed.binds === "object", "live bind inventory missing");

  const features = new Set();
  for (const binds of Object.values(parsed.binds)) {
    if (!Array.isArray(binds))
      continue;
    for (const bind of binds) {
      const feature = featureFor(bind?.action);
      if (feature)
        features.add(feature);
    }
  }

  const required = [
    "App Launcher",
    "Terminal",
    "Settings",
    "Lock Screen",
    "Control Center",
    "Clipboard",
    "Task Manager",
    "Notifications",
    "CyShell Agent",
    "Stop Agent Control",
    "Rescue CyBar",
  ];
  const missing = required.filter(name => !features.has(name));
  assert(missing.length === 0, "Welcome mapping misses live shortcuts: " + missing.join(", "));
  console.log("LABWC LIVE KEYBINDS VERIFY PASSED");
}

function verifyRuntime() {
  let state = "";
  try {
    state = execFileSync("systemctl", ["--user", "is-active", "cyshell.service"], { encoding: "utf8" }).trim();
  } catch (error) {
    fail("cyshell.service is not active: " + String(error.stdout || error.message));
  }
  assert(state === "active", "cyshell.service state is " + state);

  const runtimeDir = process.env.XDG_RUNTIME_DIR || `/run/user/${process.getuid()}`;
  const sockets = fs.readdirSync(runtimeDir).filter(name => /^cyshell-.*\.sock$/.test(name));
  assert(sockets.length > 0, "CyShell core socket is missing");

  try {
    const welcome = execFileSync("cyshell", ["ipc", "call", "welcome", "open"], { encoding: "utf8" }).trim();
    assert(welcome.includes("WELCOME_OPEN_SUCCESS"), "Welcome IPC did not open the modal");
    const keybinds = execFileSync("cyshell", ["ipc", "call", "settings", "openWith", "keybinds"], { encoding: "utf8" }).trim();
    assert(keybinds.includes("SETTINGS_OPEN_SUCCESS"), "Keybinds Settings IPC did not open the page");
    execFileSync("sleep", ["1"]);
  } catch (error) {
    fail("failed to exercise Welcome/Keybinds UI: " + String(error.stdout || error.stderr || error.message));
  }

  let journal = "";
  try {
    journal = execFileSync("journalctl", ["--user", "-u", "cyshell.service", "--since", "-2 min", "--no-pager"], { encoding: "utf8" });
  } catch (error) {
    journal = String(error.stdout || "");
  }
  const bad = /Failed to load configuration|ReferenceError|TypeError|Cannot call|GreeterCompletePage\.qml.*(?:error|Error)|KeybindsService\.qml.*(?:error|Error)|KeybindsTab\.qml.*(?:error|Error)|KeybindItem\.qml.*(?:error|Error)/;
  const match = journal.match(bad);
  assert(!match, "recent CyShell log contains QML/runtime failure: " + match?.[0]);

  try {
    execFileSync("cyshell", ["ipc", "call", "settings", "close"], { stdio: "ignore" });
  } catch {}

  console.log("CYSHELL RUNTIME VERIFY PASSED");
}

switch (process.argv[2]) {
case "source":
  verifySource();
  break;
case "live":
  verifyLive();
  break;
case "runtime":
  verifyRuntime();
  break;
default:
  console.error("usage: node scripts/verify-greeter-labwc.mjs <source|live|runtime>");
  process.exit(2);
}
