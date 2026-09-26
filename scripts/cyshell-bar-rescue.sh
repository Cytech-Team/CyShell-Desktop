#!/usr/bin/env bash
set -uo pipefail

CYSHELL_BIN="${CYSHELL_BIN:-/usr/local/bin/cyshell}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
BACKUP_DIR="$STATE_HOME/cyshell/bar-rescue"
mkdir -p "$BACKUP_DIR"

settings=""
for candidate in \
  "${XDG_CONFIG_HOME:-$HOME/.config}/CyShell/settings.json" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/settings.json"
do
  if [ -f "$candidate" ]; then
    settings="$candidate"
    break
  fi
done

# Best-effort soft recovery while the shell is still responsive.
if [ -x "$CYSHELL_BIN" ]; then
  "$CYSHELL_BIN" ipc call bar reveal id default >/dev/null 2>&1 || true
  "$CYSHELL_BIN" ipc call bar manualHide id default >/dev/null 2>&1 || true
  "$CYSHELL_BIN" ipc call bar setPosition id default bottom >/dev/null 2>&1 || true
fi

if [ -n "$settings" ]; then
  stamp="$(date +%Y%m%d-%H%M%S)"
  cp -a "$settings" "$BACKUP_DIR/settings-$stamp.json"

  python3 - "$settings" <<'PY'
import json
import os
import sys
import tempfile

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

bars = data.get("barConfigs")
if not isinstance(bars, list):
    raise SystemExit("barConfigs is missing or invalid")

target = None
for bar in bars:
    if isinstance(bar, dict) and bar.get("id") == "default":
        target = bar
        break
if target is None:
    for bar in bars:
        if isinstance(bar, dict) and not bar.get("island", False):
            target = bar
            break
if target is None:
    raise SystemExit("no recoverable CyBar configuration found")

# Recovery changes only geometry/input/visibility. Visual customization is preserved.
target.update({
    "enabled": True,
    "visible": True,
    "position": 1,
    "screenPreferences": ["all"],
    "showOnLastDisplay": True,
    "autoHide": False,
    "clickThrough": False,
    "attachToScreenEdge": True,
    "barInsetPadding": 0,
    "barLengthPadding": 0,
    "bottomGap": 0,
})

folder = os.path.dirname(path) or "."
fd, tmp = tempfile.mkstemp(prefix=".cyshell-bar-rescue-", suffix=".json", dir=folder)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
finally:
    try:
        os.unlink(tmp)
    except FileNotFoundError:
        pass
PY

  # Keep only the most recent five rescue snapshots.
  ls -1t "$BACKUP_DIR"/settings-*.json 2>/dev/null | tail -n +6 | xargs -r rm -f --
fi

systemctl --user restart dms.service
for _ in $(seq 1 50); do
  if systemctl --user is-active --quiet dms.service; then
    break
  fi
  sleep 0.1
done

sleep 0.35
if [ -x "$CYSHELL_BIN" ]; then
  "$CYSHELL_BIN" ipc call bar reveal id default >/dev/null 2>&1 || true
  "$CYSHELL_BIN" ipc call bar manualHide id default >/dev/null 2>&1 || true
  "$CYSHELL_BIN" ipc call bar setPosition id default bottom >/dev/null 2>&1 || true
fi

if command -v notify-send >/dev/null 2>&1; then
  notify-send -a "CyShell" "CyBar recovered" "Visible, bottom edge, input restored" >/dev/null 2>&1 || true
fi
