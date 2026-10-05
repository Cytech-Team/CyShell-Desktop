#!/usr/bin/env bash
# Compares `cyshell ipc call` (direct socket) against `qs ipc call` on the same call.
#   ITERATIONS=50 WARMUPS=3 CALL="lock isLocked" scripts/benchmark-ipc.sh
set -euo pipefail

ITERATIONS="${ITERATIONS:-50}"
WARMUPS="${WARMUPS:-3}"
CALL="${CALL:-lock isLocked}"
CYSHELL_BIN="${CYSHELL_BIN:-cyshell}"
QS_BIN="${QS_BIN:-qs}"

for bin in "$CYSHELL_BIN" "$QS_BIN"; do
    command -v "$bin" >/dev/null 2>&1 || { echo "not found: $bin" >&2; exit 1; }
done

# shellcheck disable=SC2206
call=($CALL)
if [[ -n "${QS_ARGS:-}" ]]; then
    # shellcheck disable=SC2206
    qs_args=($QS_ARGS)
else
    runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    state_file="$runtime_dir/cyshell.path"
    legacy_state_file="$runtime_dir/danklinux.path"
    if [[ -f "$state_file" ]]; then
        config_path="$(cat "$state_file" 2>/dev/null || true)"
    else
        config_path="$(cat "$legacy_state_file" 2>/dev/null || true)"
    fi
    [[ -n "$config_path" ]] || { echo "no running CyShell (runtime path marker missing)" >&2; exit 1; }
    qs_args=(-p "$config_path")
fi

run_cyshell() { "$CYSHELL_BIN" ipc call "${call[@]}"; }
run_qs() { "$QS_BIN" "${qs_args[@]}" ipc call "${call[@]}"; }

cyshell_out="$(run_cyshell)" || { echo "cyshell ipc call failed" >&2; exit 1; }
qs_out="$(run_qs)" || { echo "qs ipc call failed" >&2; exit 1; }
if [[ "$cyshell_out" != "$qs_out" ]]; then
    echo "outputs differ:" >&2
    echo "  cyshell: $cyshell_out" >&2
    echo "  qs:  $qs_out" >&2
    exit 1
fi

measure() {
    local fn="$1" i start end
    for ((i = 0; i < WARMUPS; i++)); do "$fn" >/dev/null; done
    for ((i = 0; i < ITERATIONS; i++)); do
        start=$(date +%s%N)
        "$fn" >/dev/null
        end=$(date +%s%N)
        echo $((end - start))
    done
}

summarize() {
    sort -n | awk '
        { v[NR] = $1; sum += $1 }
        END {
            median = (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2
            printf "%.2f | %.2f | %.2f", v[1] / 1e6, median / 1e6, sum / NR / 1e6
        }'
}

cyshell_stats="$(measure run_cyshell | summarize)"
qs_stats="$(measure run_qs | summarize)"

cat <<TABLE
IPC benchmark: \`$CALL\` ($ITERATIONS iterations, $WARMUPS warmups)
Output: $cyshell_out

| Command | Min (ms) | Median (ms) | Average (ms) |
|---|---:|---:|---:|
| cyshell ipc call | $cyshell_stats |
| qs ${qs_args[*]} ipc call | $qs_stats |
TABLE
