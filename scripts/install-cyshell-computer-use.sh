#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="/usr/local/lib/cyshell/cyshell-computer-use"
ENV_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d"
ENV_FILE="$ENV_DIR/90-cyshell-computer-use.conf"
SYSTEM_DESKTOP="/usr/share/applications/codex-desktop.desktop"
USER_DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
USER_DESKTOP="$USER_DESKTOP_DIR/codex-desktop.desktop"
TMP_BIN="$(mktemp "${TMPDIR:-/tmp}/cyshell-computer-use.XXXXXX")"
TMP_DESKTOP=""
trap 'rm -f "$TMP_BIN" "${TMP_DESKTOP:-}"' EXIT

(
  cd "$ROOT/core"
  go test ./cmd/cyshell-computer-use
  go build -o "$TMP_BIN" ./cmd/cyshell-computer-use
)

install_backend() {
  if [ "$(id -u)" -eq 0 ]; then
    install -d -m 0755 "$(dirname "$BACKEND")"
    install -m 0755 "$TMP_BIN" "$BACKEND"
  else
    command -v sudo >/dev/null 2>&1 || {
      printf 'sudo is required to install %s\n' "$BACKEND" >&2
      exit 1
    }
    sudo install -d -m 0755 "$(dirname "$BACKEND")"
    sudo install -m 0755 "$TMP_BIN" "$BACKEND"
  fi
}

install_backend

mkdir -p "$ENV_DIR"
cat > "$ENV_FILE" <<EOF
CODEX_LINUX_COMPUTER_USE_BACKEND_SOURCE=$BACKEND
EOF

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user set-environment "CODEX_LINUX_COMPUTER_USE_BACKEND_SOURCE=$BACKEND" || true
fi

if [ -f "$SYSTEM_DESKTOP" ]; then
  mkdir -p "$USER_DESKTOP_DIR"
  TMP_DESKTOP="$(mktemp "${TMPDIR:-/tmp}/codex-desktop.XXXXXX.desktop")"
  awk -v backend="$BACKEND" '
    /^Exec=env / && index($0, "CODEX_LINUX_COMPUTER_USE_BACKEND_SOURCE=") == 0 {
      sub(/^Exec=env /, "Exec=env CODEX_LINUX_COMPUTER_USE_BACKEND_SOURCE=" backend " ")
    }
    { print }
  ' "$SYSTEM_DESKTOP" > "$TMP_DESKTOP"
  install -m 0644 "$TMP_DESKTOP" "$USER_DESKTOP"
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$USER_DESKTOP_DIR" >/dev/null 2>&1 || true
  fi
fi

"$BACKEND" doctor

printf 'CyShell Computer Use installed: %s\n' "$BACKEND"
printf 'ChatGPT Community backend override: %s\n' "$ENV_FILE"
if [ -f "$USER_DESKTOP" ]; then
  printf 'Desktop launcher override: %s\n' "$USER_DESKTOP"
fi
