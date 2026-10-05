#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
APP=/opt/codex-desktop
BUILDER="$APP/update-builder"
FEATURE="$BUILDER/linux-features/computer-use-linux"
UNIFIED="$APP/resources/plugins/openai-bundled/plugins/unified-computer-use"
SETTINGS_PLUGIN="$APP/resources/plugins/openai-bundled/plugins/computer-use"
SOURCE_SETTINGS_PLUGIN="$BUILDER/plugins/openai-bundled/plugins/computer-use"
BACKEND_SOURCE=/usr/local/lib/cyshell/cyshell-computer-use
LOGO_SOURCE=/home/namkrub/Downloads/CyShell.png
BROWSER_MCP_SOURCE="$SCRIPT_DIR/cyshell-browser-mcp.mjs"
BACKUP="$APP/.cyshell-built-in-backup"

test -x "$BACKEND_SOURCE"
test -f "$LOGO_SOURCE"
test -f "$BROWSER_MCP_SOURCE"
test -f "$APP/resources/app.asar"

mkdir -p "$BACKUP"
backup_once() {
  local src="$1"
  local name="$2"
  if [ -e "$src" ] && [ ! -e "$BACKUP/$name" ]; then
    cp -a --reflink=auto "$src" "$BACKUP/$name"
  fi
}

backup_once "$FEATURE/host-service.mjs" feature-host-service.mjs
backup_once "$APP/.codex-linux/features/computer-use-linux/host-service.mjs" runtime-host-service.mjs
backup_once "$FEATURE/stage.sh" stage.sh
backup_once "$FEATURE/stage.js" stage.js
backup_once "$FEATURE/settings.js" settings.js
backup_once "$FEATURE/patch.js" patch.js
backup_once "$FEATURE/feature.json" feature.json
backup_once "$SOURCE_SETTINGS_PLUGIN/.codex-plugin/plugin.json" source-plugin.json
backup_once "$SETTINGS_PLUGIN/.codex-plugin/plugin.json" runtime-plugin.json
backup_once "$APP/resources/app.asar" app.asar

install -m 0755 "$BACKEND_SOURCE" "$FEATURE/cyshell-computer-use"
install -m 0755 "$BACKEND_SOURCE" "$UNIFIED/bin/cyshell-computer-use"
install -m 0644 "$LOGO_SOURCE" "$FEATURE/CyShell.png"
install -d -m 0755 "$SOURCE_SETTINGS_PLUGIN/assets" "$SETTINGS_PLUGIN/assets"
install -m 0644 "$LOGO_SOURCE" "$SOURCE_SETTINGS_PLUGIN/assets/app-icon.png"
install -m 0644 "$LOGO_SOURCE" "$SETTINGS_PLUGIN/assets/app-icon.png"
install -m 0755 "$BROWSER_MCP_SOURCE" "$SOURCE_SETTINGS_PLUGIN/cyshell-browser-mcp.mjs"
install -m 0755 "$BROWSER_MCP_SOURCE" "$SETTINGS_PLUGIN/cyshell-browser-mcp.mjs"
cat >"$SOURCE_SETTINGS_PLUGIN/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "cyshell_browser": {
      "command": "/opt/codex-desktop/resources/cua_node/bin/node",
      "args": ["./cyshell-browser-mcp.mjs"],
      "cwd": ".",
      "enabled": true,
      "omit_tools_from": ["deferred"],
      "default_tools_approval_mode": "approve",
      "startup_timeout_sec": 10,
      "tool_timeout_sec": 60
    }
  }
}
JSON
install -m 0644 "$SOURCE_SETTINGS_PLUGIN/.mcp.json" "$SETTINGS_PLUGIN/.mcp.json"

python3 - "$FEATURE/host-service.mjs" "$APP/.codex-linux/features/computer-use-linux/host-service.mjs" <<'PY'
from pathlib import Path
import sys
old = """function exactBackendPath(env) {
  const appDir = env.CODEX_LINUX_APP_DIR;
  const override = env.CODEX_LINUX_COMPUTER_USE_BACKEND_SOURCE?.trim();
  const backend = override || (appDir && path.join(appDir, 'resources/plugins/openai-bundled/plugins/unified-computer-use/bin/codex-computer-use-linux'));
"""
new = """function exactBackendPath(env) {
  const appDir = env.CODEX_LINUX_APP_DIR;
  const backend = appDir && path.join(appDir, 'resources/plugins/openai-bundled/plugins/unified-computer-use/bin/cyshell-computer-use');
"""
for name in sys.argv[1:]:
    p = Path(name)
    s = p.read_text()
    if old in s:
        s = s.replace(old, new, 1)
    elif new not in s:
        raise SystemExit(f"unexpected backend resolver in {p}")
    s = s.replace("Linux Computer Use backend path is unavailable", "CyShell Built-in backend path is unavailable")
    s = s.replace("Linux Computer Use backend is not a regular file", "CyShell Built-in backend is not a regular file")
    p.write_text(s)
PY

python3 - "$FEATURE/stage.sh" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
needle = 'cosmic="${CODEX_COMPUTER_USE_COSMIC_BINARY_SOURCE:-$SCRIPT_DIR/target/release/codex-computer-use-cosmic}"\n'
add = needle + 'cyshell_backend="${CYSHELL_COMPUTER_USE_BINARY_SOURCE:-$SCRIPT_DIR/cyshell-computer-use}"\n'
if 'cyshell_backend=' not in s:
    if needle not in s:
        raise SystemExit("stage.sh backend header changed")
    s = s.replace(needle, add, 1)
check = '''[ -x "$cosmic" ] || {
    echo "Linux Computer Use is enabled but its COSMIC helper is missing: $cosmic" >&2
    exit 1
}
'''
check_new = check + '''[ -x "$cyshell_backend" ] || {
    echo "CyShell Built-in is enabled but its backend is missing: $cyshell_backend" >&2
    exit 1
}
'''
if 'CyShell Built-in is enabled but its backend is missing' not in s:
    if check not in s:
        raise SystemExit("stage.sh validation block changed")
    s = s.replace(check, check_new, 1)
install_line = 'install -m 0755 "$cosmic" "$target/bin/codex-computer-use-cosmic"\n'
install_new = install_line + 'install -m 0755 "$cyshell_backend" "$target/bin/cyshell-computer-use"\n'
if 'target/bin/cyshell-computer-use' not in s:
    if install_line not in s:
        raise SystemExit("stage.sh install block changed")
    s = s.replace(install_line, install_new, 1)
p.write_text(s)
PY

python3 - "$FEATURE/stage.js" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
s = s.replace('"-linux-native.6"', '"-linux-native.7"')
needle = 'fs.copyFileSync(path.join(settingsSource, ".codex-plugin/plugin.json"), path.join(settingsTarget, ".codex-plugin/plugin.json"));\n'
addition = needle + 'fs.mkdirSync(path.join(settingsTarget, "assets"), { recursive: true });\nfs.copyFileSync(path.join(__dirname, "CyShell.png"), path.join(settingsTarget, "assets/app-icon.png"));\n'
if 'settingsTarget, "assets/app-icon.png"' not in s:
    if needle not in s:
        raise SystemExit("stage.js settings copy contract changed")
    s = s.replace(needle, addition, 1)
p.write_text(s)
PY

python3 - "$FEATURE/settings.js" "$FEATURE/patch.js" <<'PY'
from pathlib import Path
import sys
settings = Path(sys.argv[1])
s = settings.read_text()
fn = r'''
function applyCyShellBuiltInBrandingPatch(source) {
  const originalTitle = "id:`settings.computerUse.anyApp.title`,defaultMessage:`Any App`";
  const brandedTitle = "id:`settings.computerUse.anyApp.title`,defaultMessage:`CyShell Built-in`";
  const originalDescription = "id:`settings.computerUse.anyApp.description`,defaultMessage:`Let ChatGPT control apps on your computer`";
  const brandedDescription = "id:`settings.computerUse.anyApp.description`,defaultMessage:`Built-in CyShell control for apps on your computer`";
  const count = (text, needle) => text.split(needle).length - 1;
  const originalCount = count(source, originalTitle) + count(source, originalDescription);
  const brandedCount = count(source, brandedTitle) + count(source, brandedDescription);
  if (originalCount === 0 && brandedCount === 2) return source;
  if (originalCount !== 2 || brandedCount !== 0) {
    throw new Error("CyShell Built-in Settings branding contract missing or ambiguous");
  }
  return source.replace(originalTitle, brandedTitle).replace(originalDescription, brandedDescription);
}

'''
if 'function applyCyShellBuiltInBrandingPatch' not in s:
    marker = 'module.exports = {\n'
    if marker not in s:
        raise SystemExit("settings.js export marker changed")
    s = s.replace(marker, fn + marker, 1)
old_exports = '''module.exports = {
  applyNativeSettingsAvailabilityPatch,
  applyNativeSettingsVisibilityPatch,
  matchesNativeSettingsVisibilityContract,
};
'''
new_exports = '''module.exports = {
  applyCyShellBuiltInBrandingPatch,
  applyNativeSettingsAvailabilityPatch,
  applyNativeSettingsVisibilityPatch,
  matchesNativeSettingsVisibilityContract,
};
'''
if old_exports in s:
    s = s.replace(old_exports, new_exports, 1)
elif new_exports not in s:
    raise SystemExit("settings.js exports changed")
settings.write_text(s)

patch = Path(sys.argv[2])
s = patch.read_text()
old_import = '''const {
  applyNativeSettingsAvailabilityPatch,
  applyNativeSettingsVisibilityPatch,
  matchesNativeSettingsVisibilityContract,
} = require("./settings.js");
'''
new_import = '''const {
  applyCyShellBuiltInBrandingPatch,
  applyNativeSettingsAvailabilityPatch,
  applyNativeSettingsVisibilityPatch,
  matchesNativeSettingsVisibilityContract,
} = require("./settings.js");
'''
if old_import in s:
    s = s.replace(old_import, new_import, 1)
elif new_import not in s:
    raise SystemExit("patch.js settings import changed")
descriptor = '''  webviewAssetPatch({
    id: "cyshell-built-in-branding",
    phase: "webview-asset",
    order: 20_145,
    ciPolicy: "optional",
    pattern: /^computer-use-settings-[^.]+\\.js$/,
    missingDescription: "Computer Use settings bundle for CyShell branding",
    skipDescription: "CyShell Built-in Settings branding patch",
    apply: applyCyShellBuiltInBrandingPatch,
  }),
'''
if 'id: "cyshell-built-in-branding"' not in s:
    anchor = '''  webviewAssetPatch({
    id: "host-platform",
'''
    if anchor not in s:
        raise SystemExit("patch.js host-platform descriptor changed")
    s = s.replace(anchor, descriptor + anchor, 1)
patch.write_text(s)
PY

python3 - "$FEATURE/feature.json" "$SOURCE_SETTINGS_PLUGIN/.codex-plugin/plugin.json" "$SETTINGS_PLUGIN/.codex-plugin/plugin.json" <<'PY'
from pathlib import Path
import json, sys
feature = Path(sys.argv[1])
data = json.loads(feature.read_text())
data["title"] = "CyShell Built-in"
data["description"] = "Built-in CyShell desktop-control integration for ChatGPT Community on Linux."
feature.write_text(json.dumps(data, indent=2) + "\n")

for name in sys.argv[2:]:
    p = Path(name)
    data = json.loads(p.read_text())
    data["version"] = "0.2.1-cyshell-built-in"
    data["description"] = "CyShell Built-in desktop and visual browser control for ChatGPT Community on Linux."
    data["mcpServers"] = "./.mcp.json"
    data["author"] = {"name": "Cytech Team Development"}
    interface = data.setdefault("interface", {})
    interface["displayName"] = "CyShell Built-in"
    interface["shortDescription"] = "Built-in CyShell desktop + visual browser control"
    interface["longDescription"] = "CyShell Built-in lets ChatGPT Community inspect and control Linux desktop apps and the user's connected browser through the CyCom extension. Browser control can enumerate real tabs, read page state, capture screenshots, and send pointer, keyboard, and navigation actions in the user's normal browser profile. Actions can change page state and may focus a tab or window, including during capture; the browser is not isolated. Desktop screenshots, accessibility metadata, window control, and input are routed through CyShell. CyShell native state is authoritative for readiness."
    interface["developerName"] = "Cytech Team Development"
    interface["logo"] = "./assets/app-icon.png"
    interface["defaultPrompt"] = [
        "Check whether CyShell Built-in native backend is ready",
        "List running desktop apps through CyShell",
        "Inspect and control the CyShell browser visually"
    ]
    interface["brandColor"] = "#42A5F5"
    p.write_text(json.dumps(data, indent=2) + "\n")
PY

python3 - "$FEATURE/README.md" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
s = s.replace("# Linux Computer Use", "# CyShell Built-in", 1)
s = s.replace("Disabled-by-default Linux Computer Use integration.", "CyShell Built-in desktop-control integration.")
s = s.replace("In Settings → Computer use, **Any App** controls native access.", "In Settings → Computer use, **CyShell Built-in** controls native access.")
s = s.replace("The separate `computer-use` component stores the Any App setting", "The separate `computer-use` component stores the CyShell Built-in setting")
p.write_text(s)
PY

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
npx --yes @electron/asar extract "$APP/resources/app.asar" "$work/app"
if [ -d "$APP/resources/app.asar.unpacked" ]; then
  cp -a "$APP/resources/app.asar.unpacked/." "$work/app/"
fi
settings_asset="$(find "$work/app/webview/assets" -maxdepth 1 -type f -name 'computer-use-settings-*.js' -print -quit)"
test -n "$settings_asset"
python3 - "$settings_asset" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
pairs = [
    ("id:`settings.computerUse.anyApp.title`,defaultMessage:`Any App`",
     "id:`settings.computerUse.anyApp.title`,defaultMessage:`CyShell Built-in`"),
    ("id:`settings.computerUse.anyApp.description`,defaultMessage:`Let ChatGPT control apps on your computer`",
     "id:`settings.computerUse.anyApp.description`,defaultMessage:`Built-in CyShell control for apps on your computer`"),
]
for old, new in pairs:
    old_count = s.count(old)
    new_count = s.count(new)
    if old_count == 1 and new_count == 0:
        s = s.replace(old, new, 1)
    elif old_count == 0 and new_count == 1:
        pass
    else:
        raise SystemExit(f"unexpected Computer Use branding contract: old={old_count} new={new_count}")
p.write_text(s)
PY
(cd "$work/app" && find . -type f -printf '%P\n' | LC_ALL=C sort) > "$work/ordering"
npx --yes @electron/asar pack "$work/app" "$work/app.asar" \
  --ordering "$work/ordering" \
  --unpack "{*.node,*.so,*.dylib}"
install -m 0644 "$work/app.asar" "$APP/resources/app.asar"
if [ -d "$work/app.asar.unpacked" ]; then
  rm -rf "$APP/resources/app.asar.unpacked"
  mv "$work/app.asar.unpacked" "$APP/resources/app.asar.unpacked"
fi

echo CYSHELL_BUILTIN_PATCH_APPLIED
