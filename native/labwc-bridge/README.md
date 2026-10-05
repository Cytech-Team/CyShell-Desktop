# CyShell LabWC bridge

This directory owns CyShell's private, in-process LabWC adapter and its local
socket API. LabWC and wlroots own their implementation and ABI; their internal
structures must not become a second interface exposed to shell consumers.
`quickshell/Services/LabwcBridgeService.qml` consumes the bridge API and should
not need compositor-version branches when an adapter is ported.

## Compatibility boundary

`compatibility.conf` is the single declaration of the exact supported LabWC
release and wlroots major/minor ABI. The initial declaration preserves LabWC
`0.20.2` with wlroots `0.20`. A patch, development, or otherwise different LabWC
version is unsupported until separately reviewed. Do not replace the exact
release with a range or a prefix match.

The file contains exactly the three `KEY=value` declarations shown in the
checked-in file. Values are unquoted decimal numbers; the LabWC value has three
components. Blank lines and comments beginning with `#` are allowed. Duplicate
keys, unknown keys, whitespace around assignments, missing values, leading
zeroes, and shell expressions are rejected by the session wrapper.

The native Makefile includes this file, derives the wlroots pkg-config package,
and passes the declaration as C preprocessor definitions. The bridge rejects
headers from a different wlroots major/minor ABI at compilation. The library
depends on the declaration and Makefile so changes trigger a rebuild.

## Session startup

Use `scripts/cyshell-labwc-session`, installed as
`/usr/local/bin/cyshell-labwc-session` by the existing bridge target. It reads
`compatibility.conf` beside the selected library as data, without sourcing it.
The existing overrides remain available:

- `CYSHELL_LABWC_BIN` selects the compositor, defaulting to `/usr/bin/labwc`.
- `CYSHELL_LABWC_BRIDGE_LIB` selects the library, defaulting to
  `/usr/local/lib/cyshell/libcyshell-labwc-bridge.so`. Keep its matching metadata
  in the same directory, including with a custom installation prefix.

Help, version, exit, and reconfigure invocations go directly to the selected
compositor. For a session launch, the wrapper invokes that binary once with
`--version`, with `LD_PRELOAD` unset inside the probe only. It accepts a single
line beginning with `labwc `, followed by an exact matching version token.
The same line must contain exactly one whitespace-separated
`wlroots-X.Y` or `wlroots-X.Y.Z` token with canonical decimal components.
Its major/minor must match the declared ABI; a numeric patch component is
accepted without expanding that ABI boundary. Other build details are ignored.
For example, `labwc 0.20.2 (+xwayland +nls +rsvg +libsfdo) wlroots-0.20.2`
identifies LabWC `0.20.2` and wlroots ABI `0.20`. Only after both checks pass is
the observed LabWC token exported as `CYSHELL_LABWC_VERSION` and the bridge
added to `LD_PRELOAD`. Callers should not set this internal handoff variable.

Missing or malformed metadata, a missing library, a failed version command,
unrecognized output, an unsupported release, or a missing, malformed,
duplicate/ambiguous, or mismatched wlroots token produces a concise stderr
diagnostic and executes the compositor with the original arguments without
adding the bridge. Existing `LD_PRELOAD` entries are preserved for the final
exec, including on fallback; globally preloading the bridge bypasses the
wrapper's loading protection and is not a supported launch route.

The bridge checks the handoff version against its compiled declaration and
checks the loaded wlroots major/minor before either create hook attaches
listeners to wlroots structures. It checks compatibility again before opening
the socket. Status reports the observed version. These checks do not establish
compatibility of a patched compositor that reports the same version, nor can
they undo the dynamic loader's work after a library has already been preloaded.
Keep the wrapper, library, and metadata from the same build together.

The wlroots preflight addresses review finding F1: a supported LabWC release
can be built against a different wlroots ABI. The C checks happen after preload,
and interposed functions still forward calls, so constructor rejection alone
cannot protect calls through an incompatible function signature. The wrapper
must reject the reported ABI before adding the library.

Startup adds one short version probe and shell parsing. It adds no background
process, idle polling, timer, or retained allocation to the running session.

## API ownership

`bridge.c` is the authority for API version 2. Requests and responses remain
newline-delimited JSON over `$XDG_RUNTIME_DIR/cyshell-labwc.sock`, with socket
mode `0600` for the session user. API v1 methods remain `status`,
`capabilities`, `windows.list`, `window.close`, `pointer.output`,
`events.subscribe`, and `events.unsubscribe`. The advertised capability names
are `windows.list`, `window.close`, `pointer.output`, `events.subscribe`, and
`events.unsubscribe`. The v2 capability list adds `keyboard.layout.status` and
`keyboard.layout.cycle`.

`keyboard.layout.status` returns `{"ok":true,"group":N,"layouts":M}`.
`group` is the current zero-based keyboard layout group, and `layouts` is the
number of layouts in the configured keymap. `keyboard.layout.cycle` advances
the group by one, wrapping to zero, and returns the resulting `group` and
`layouts` in the same form. Both methods return
`{"ok":false,"error":"keyboard layout unavailable"}` when the bridge has no
tracked keyboard group/member or the first tracked member has no usable keymap
or configured layouts. Cycle returns
`{"ok":false,"error":"only one keyboard layout configured"}` when fewer than
two layouts are configured.

These methods inspect the first keyboard group created by the compositor and
the first currently tracked member of that group. They report and change that
member's compositor keyboard group; they do not query the QML language service.
Layout changes do not emit bridge events or notifications. The QML shell's
keyboard service still uses `cyshell-language` and has not migrated to this API.

`pointer.output` reports the LabWC output beneath the compositor's current
cursor together with its layout coordinates. CyStart's keyboard shortcut uses
this API so output selection does not depend on XWayland's separate screen
coordinates. A cursor in an output gap, or a bridge that does not support the
method, returns an empty screen and lets the shell use its normal focus-based
fallback.

Keep window IDs, events, response fields, and command semantics stable while
adapting compositor internals. Future focus, move, resize, workspace, or other
commands require a separate API design and consumer review; changing an ABI
declaration does not introduce such capabilities.

## Porting to a new LabWC or wlroots version

1. Record the candidate release, its actual `--version` output, and its wlroots
   build dependency. Review the matching upstream source and any distribution
   patches. A matching reported version alone is not ABI evidence.
2. Review every interposed function signature, accessed structure member,
   listener lifetime, and XDG/Xwayland event used in `bridge.c`. Update this
   adapter behind the existing API. Keep the compatibility gate before any
   listener accesses private layouts.
3. Change `compatibility.conf` only after the adapter review establishes the
   exact supported release and ABI. This adapter supports one declared release;
   supporting multiple versions needs an explicit adapter-selection design.
4. In an isolated development environment, rebuild the bridge against the
   declared headers and libraries. Exercise known, unsupported, unknown, and
   failed version probes; missing and invalid metadata; custom binary/library
   paths; existing preloads; management invocations; and argument forwarding.
   Include absent, malformed, duplicate, and mismatched wlroots version tokens.
   Confirm unsupported releases and ABIs start without a newly added CyShell
   preload.
5. In an isolated compositor session, verify native Wayland and Xwayland window
   lifetimes, listing, close behavior, subscriptions, API v1 fields/capabilities,
   socket permissions, disconnect/reconnect behavior, and idle resource use.
   Check that a compiled/runtime ABI mismatch disables bridge hooks.
6. Package and deploy the rebuilt library, matching compatibility file, and
   wrapper together through the bridge install target. Its uninstall target
   removes the metadata too. Session activation requires a separately planned
   login/session restart; do not hot-inject this library into a running LabWC.

The compatibility gate change itself has received source inspection only.
No build, test execution, installation, or live-session validation was performed
as part of that change.
