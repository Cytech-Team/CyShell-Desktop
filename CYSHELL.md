# CyShell Desktop

CyShell Desktop is a modern, ready-to-use desktop shell and an extensible shell framework.

This repository is forked from DankMaterialShell (DMS) to accelerate development. CyShell is not intended to be a visual rebrand of DMS. The fork is a bootstrap base while the architecture is progressively separated into CyShell-owned runtime, compatibility, layout, agent, and customization layers.

## Core principles

1. **Ready shell + framework**
   - CyShell must work immediately after installation.
   - The same public framework APIs used by third-party components should be used by the default shell.

2. **Full customization without source editing**
   - Users can attach, detach, move, resize, group, split, dock, float, stack, and restyle shell components through the UI.
   - Panels, launchers, quick settings, notifications, widgets, and desktop surfaces are composable components rather than fixed UI positions.

3. **Cross-shell compatibility**
   - Native CyShell extensions are first-class.
   - Compatibility hosts/adapters may support DMS, Noctalia, scripts, D-Bus services, and other ecosystems without pretending their APIs are identical.
   - External notification, launcher, bar, wallpaper, lock, and OSD providers can coexist with CyShell.

4. **Agent-native desktop**
   - CyCom is embedded in the CyShell core as the built-in computer runtime.
   - CyShell exposes structured desktop state and semantic actions so agents do not have to rely on screenshots, OCR, or shell/config discovery for native desktop operations.
   - CyCom policy, audit, reason validation, computer-use fallbacks, jobs, targets, filesystem, process, service, and network capabilities remain available below the semantic shell layer.

5. **Update-safe customization**
   - User customization is stored as stable component/layout data and overlays, not line-number patches.
   - Deep source overrides live outside upstream-owned files.
   - Components have stable IDs and API versions.
   - Updates use compatibility checks and migration paths; user overrides should not be silently overwritten.

6. **Compositor abstraction**
   - Labwc is the first-class development target.
   - Compositor-specific logic belongs behind a backend API so Hyprland, Niri, Sway, and others can be added later.

7. **Open development**
   - Preserve upstream attribution and license requirements.
   - Keep the upstream remote usable so selected DMS fixes can be reviewed and incorporated deliberately.

## Architecture

```text
Human / external MCP client / built-in Assistant
                     |
               CyShell Agent
                     |
          Embedded CyCom Runtime
      registry / policy / audit / jobs
            /                 \
 CyShell semantic APIs       computer APIs
 settings / UI / windows     files / process
 workspaces / surfaces       network / services
            \                 /
              CyShell Core
          state / IPC / backends
                     |
        compositor + Linux services
```

The default Agent path is in-process. CyShell does not require a separate CyCom daemon for its built-in Agent.

## Agent runtime

CyCom source is pinned under `agent/cycom/runtime` as a Git submodule so CyCom keeps its own release history while CyShell imports its public `embed` package directly.

CyShell registers native tools into the same CyCom registry used by generic computer tools. Tool calls therefore keep CyCom's normal schema validation, required reason, policy interceptors, audit records, and host safety gates.

Current native tools include:

- `shell_get_state` — settings, session, and live desktop semantic state.
- `shell_query_ui` — search semantic shell surfaces, settings pages, windows, bars, docks, and workspaces.
- `shell_settings_get` / `shell_settings_set` — validated scalar settings access. Successful scalar writes capture the previous value and return the same short-lived semantic rollback receipt used by machine actions.
- `shell_settings_search` — semantic Settings discovery using the same translated/capability-aware search index and ranking as the native UI. Direct scalar rows expose their exact `settingKey`, current value/type, and whether the key is writable so the Agent does not guess config names.
- `shell_open_settings` — open Settings, a named page, or a search result page+section and highlight the native row.
- `shell_launcher` — open, close, toggle, or search the native launcher.
- `shell_control_center` — control the native Control Center.
- `application_search` / `application_launch` — search installed visible desktop applications using CyShell launcher ranking and launch an exact returned desktop-entry id without guessing executable commands.
- `window_list` / `window_control` — semantic Wayland toplevel inspection and actions.
- `workspace_list` / `workspace_focus` — semantic workspace inspection and activation.
- `desktop_get_context` — one structured context graph spanning shell state, machine state, permission scopes, and optional third-party app/system context. Responses include stable SHA-256 `contextDigest` / per-section digests so repeated reads can return only changed sections or a compact unchanged marker.
- `desktop_query` — one semantic query entrypoint that ranks/caps CyShell semantic matches first and falls back to a bounded focused-application accessibility query only when needed.
- `app_query_ui` — AT-SPI/Any App semantic query with screenshots disabled by default and a compact accessibility projection that preserves useful order while collapsing repeated nodes and capping context size.
- `desktop_action` — native machine actions for Wi-Fi, Bluetooth, audio, microphone, brightness, and power profile. Undoable actions capture their pre-action semantic state and return a short-lived session receipt.
- `desktop_receipts` / `desktop_undo` — list and consume single-use rollback receipts for reversible machine or scalar Settings actions without replaying raw tool arguments. Receipt listing dynamically requires `settings.read` when setting values are present, and undo dynamically requires `settings.write` or `device.control` according to the receipt kind.

The shell semantic tree now includes network, Wi-Fi, Bluetooth, audio, microphone, battery, brightness, power profile, displays, windows, workspaces, settings pages, bars, docks, and shell surfaces. Computer-use and screenshots remain fallback paths when no semantic API exists.

## Labwc native shortcut management

CyShell Settings can read and edit Labwc keyboard shortcuts directly from `~/.config/labwc/rc.xml`. The editor preserves user-owned XML and writes only a delimited **CyShell managed keybinds** block at the end of `<keyboard>`, so later Labwc bindings can safely override an existing shortcut without rewriting the original entry. Removing/resetting an override reveals the underlying user binding again. Moving an existing shortcut uses an atomic provider operation and a Labwc `None` suppression for the old key when necessary, preventing both old and new keys from firing.

Labwc edits are written atomically, XML-escaped, preserve file permissions, and trigger `labwc --reconfigure` from the running session. The editor exposes Labwc-specific `onRelease`, `allowWhenLocked`, and shortcut-inhibition controls. Agent commands (`dms agent open`, `dms agent review`, and `dms agent stop`) are first-class shortcut actions, and Settings → Agent shows the currently bound keys with direct links into the shortcut editor.

## Labwc semantic workspace backend

Labwc workspace support uses `ext-workspace-v1` directly through the shared Wayland connection.

The core tracks workspace names/IDs, coordinates, state, capabilities, groups, and output membership. It exposes live state through the core subscription system and activates a workspace with protocol requests followed by a manager commit.

This backend feeds both shell widgets and the Agent layer through the same `CompositorService` abstraction.

## Built-in Assistant

CyShell includes a native Assistant surface rather than launching an external Agent application.

The Assistant:

- runs orchestration in the CyShell core;
- calls tools through the embedded CyCom registry;
- prefers semantic CyShell APIs before computer-use fallbacks;
- supports OpenAI-compatible chat/tool-call endpoints plus native Anthropic Messages API and native Gemini `generateContent` function calling;
- replays Gemini response parts exactly during tool rounds so function IDs and thought signatures survive REST round-trips;
- defaults OpenAI-compatible mode to local `http://127.0.0.1:11434/v1` for Ollama-compatible setups;
- discovers models with the active provider's native model-list API;
- remembers endpoint/model choices independently per provider;
- persists the last conversation turns in a private `0600` state file and reloads them after a shell restart;
- cancels an in-flight provider request when the Agent emergency stop is used.

Non-secret provider settings are persisted in the CyCom state directory. Provider API keys are stored through the desktop Secret Service/keyring and are never written to the CyShell configuration file or returned through Agent state.

Environment variables can override provider configuration:

- `CYSHELL_AGENT_PROVIDER` (`openai-compatible`, `anthropic`, or `gemini`)
- `CYSHELL_AGENT_BASE_URL`
- `CYSHELL_AGENT_MODEL`
- `CYSHELL_AGENT_API_KEY`

## Agent safety controls

Settings contains a first-class **Agent** page with runtime state, provider/model configuration, native-context status, and emergency controls.

The runtime has two persistent master gates:

- **Enable Agent runtime** — disables all embedded Agent tool execution when off.
- **Allow computer control** — keeps read-only semantic/context tools available while blocking state-changing tools.

Below the master gates, CyShell enforces persistent capability scopes inside the same CyCom interceptor path. Current scopes include `desktop.read`, `desktop.control`, `settings.read`, `settings.write`, `window.read`, `window.control`, `workspace.read`, `workspace.control`, `app.read`, `app.control`, `screen.capture`, `device.control`, `files.read`, `files.write`, `system.read`, `system.control`, `network.access`, `remote.read`, `remote.control`, and `power.control`.

Scopes apply to both the built-in Assistant and external MCP clients. Some tools are argument-aware: for example, `anyapp_get_app_state` only requires `screen.capture` when screenshot output is explicitly requested.

Third-party application perception/control and screenshots add a second consent layer. Unknown apps default to **Ask**. The tool call is paused and CyShell opens a native permission dialog where the user can choose **Allow once**, **Always allow**, **Deny**, or **Always deny**. Persistent decisions are keyed to stable application IDs when available, remain subordinate to the global scope/master gates, and survive restarts. PID/title-only targets cannot be permanently trusted.

The bar includes a native Agent status indicator for armed, active, and waiting-for-permission states. Left-click opens the Assistant or pending approval; right-click performs an emergency stop. Agent state is pushed over the core subscription socket rather than polled: active-call transitions, permission changes, approval queue changes, and recent tool activity arrive as live events. Settings → Agent exposes the recent activity timeline with tool name, status, duration, reason, caller attribution, and sanitized error text without storing raw tool arguments. The built-in Assistant is identified directly; MCP transports forward the MCP `clientInfo` name/version for diagnostics (it is descriptive attribution, not a security identity).

The CLI exposes `dms agent open`, `dms agent review`, `dms agent status`, `dms agent stop`, `dms agent activity`, `dms agent receipts`, and `dms agent undo [receipt-id]` so compositors and debugging workflows can bind, inspect, and roll back semantic Agent controls without a sidecar. Omitting the receipt id rolls back the newest still-valid receipt.

**Stop control** immediately disables computer control and cancels active CyShell Agent calls. Disabling an individual permission scope also cancels active calls so an already-running operation cannot continue under a newly revoked capability. Permission state survives shell restarts.

CyCom policy and audit still apply in addition to these user-facing gates.

## MCP transport

`cyshell-mcp` is a thin stdio MCP transport for external clients such as coding/assistant hosts.

It does not instantiate another CyCom runtime. It connects to the running CyShell core over the local Unix socket and forwards:

```text
MCP client
   |
cyshell-mcp
   |
CyShell local IPC
   |
embedded CyCom registry
```

This keeps one authoritative runtime, one policy/audit path, and one set of Agent safety controls.

## Customization roadmap

### Phase 0 - Fork stabilization

- Keep `master` close to upstream DMS.
- Develop CyShell on `cyshell-dev`.
- Preserve upstream license and attribution.

### Phase 1 - Runtime and Agent boundary

- Embedded CyCom runtime: **implemented**.
- Semantic settings/UI/window/workspace tools: **initial implementation complete**.
- Labwc native workspace backend: **implemented**.
- Built-in Assistant and Agent Settings: **initial implementation complete**.

### Phase 2 - Freeform layout

- Define stable component IDs.
- Implement docked, floating, anchored, overlay, row, column, stack, grid, and freeform containers.
- Add Edit Mode with drag/drop, resize, group/ungroup, attach/detach, and per-monitor placement.

### Phase 3 - Provider and compatibility layer

- Add provider slots for notifications, launcher, taskbar, wallpaper, lock, OSD, and clipboard.
- Keep DMS compatibility during the migration.
- Prototype Noctalia/script/D-Bus adapters as separate hosts.

### Phase 4 - Agent expansion

- Fine-grained user permission scopes: **initial implementation complete**.
- Unified semantic desktop/app context graph: **initial implementation complete**.
- Native machine state/actions for network radio, Bluetooth, audio, brightness and power profile: **initial implementation complete**.
- Per-application remembered policy and one-shot approval flows: **initial implementation complete**.
- Native Agent armed/active/pending indicator and compositor-bindable stop/open/review CLI: **implemented**.
- Compact projected AT-SPI application context: **implemented**.
- Native OpenAI-compatible, Anthropic, and Gemini provider protocols with per-provider memory: **implemented**.
- Persistent Assistant conversation history: **implemented**.
- Push-based Agent state/activity/approval event stream with user-visible recent activity: **implemented**.
- Built-in/MCP client attribution in live Agent activity: **implemented**.
- Digest/delta-aware unified desktop context and ranked bounded semantic queries: **implemented**.
- Session-bound semantic action receipts with one-click/CLI rollback for reversible machine controls and scalar Settings writes: **implemented**.
- Native semantic Settings search with exact writable-key discovery and page/section navigation: **implemented**.
- Native installed-application discovery/launch using exact desktop-entry IDs: **implemented**.
- Add more semantic components/actions as the CyShell component model lands.
- Keep computer-use/vision as fallback rather than the default path.

### Phase 5 - Update-safe deep customization

- Add overlay/forked-component workflow.
- Add component API versioning and migrations.
- Add compatibility checking and visual diff/merge assistance for deep overrides.

## Branch policy

- `master`: upstream tracking baseline.
- `cyshell-dev`: active CyShell development.
- Feature work should branch from `cyshell-dev`.

## Upstream

Original project: AvengeMedia/DankMaterialShell.

CyShell continues to preserve the upstream license and attribution while separating CyShell-specific behavior from upstream DMS behavior.
