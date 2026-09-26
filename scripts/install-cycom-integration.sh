#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
core_dir="$repo_root/core"
bridge_path=${CYSHELL_AGENT_BRIDGE:-"$HOME/.local/lib/cyshell/cyshell-agent-bridge"}
state_home=${XDG_STATE_HOME:-"$HOME/.local/state"}
cycom_state_dir=${CYCOM_STATE_DIR:-"$state_home/cycomagent"}
plugin_dir="$cycom_state_dir/plugins.d"
plugin_manifest="$plugin_dir/cyshell-desktop-state.json"
template="$repo_root/agent/cycom/cyshell_desktop_state.json.in"

mkdir -p "$(dirname -- "$bridge_path")" "$plugin_dir"
tmp_bridge="$bridge_path.tmp.$$"
trap 'rm -f "$tmp_bridge"' EXIT HUP INT TERM

(
	cd "$core_dir"
	CGO_ENABLED=0 go build -o "$tmp_bridge" ./cmd/cyshell-agent-bridge
)
chmod 755 "$tmp_bridge"
mv -f "$tmp_bridge" "$bridge_path"
trap - EXIT HUP INT TERM

escaped_bridge=$(printf '%s' "$bridge_path" | sed 's/[\\&|]/\\&/g')
sed "s|@CYSHELL_AGENT_BRIDGE@|$escaped_bridge|g" "$template" > "$plugin_manifest.tmp"
chmod 600 "$plugin_manifest.tmp"
mv -f "$plugin_manifest.tmp" "$plugin_manifest"

printf 'Installed CyShell agent bridge: %s\n' "$bridge_path"
printf 'Installed CyCom plugin manifest: %s\n' "$plugin_manifest"
printf 'Reload CyCom plugins or restart CyComAgent to register cyshell_desktop_state.\n'
