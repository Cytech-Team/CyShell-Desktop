# CyCom in CyShell

CyCom is embedded into the CyShell core and is the primary Agent/computer runtime for CyShell Desktop.

## Primary architecture

```text
CyShell UI / built-in Assistant / external MCP client
                       |
                 CyShell Core
                       |
              Embedded CyCom
        registry / policy / audit
             /             \
   semantic shell tools   computer tools
```

The embedded runtime is sourced from the pinned `agent/cycom/runtime` submodule. CyShell imports CyCom's public `embed` package in-process, then registers CyShell-native semantic tools into the same registry.

This means native shell actions and generic computer actions share the same validation, policy, audit, and user control gates.

## Native semantic surface

CyShell currently exposes native Agent capabilities for:

- full shell/settings/session and machine context;
- unified `desktop_get_context` / `desktop_query` semantic discovery with digest/delta responses, semantic ranking, and bounded result sets;
- compact projected third-party app accessibility queries through Any App / AT-SPI;
- semantic Settings search/get/set/open, plus Launcher, Control Center, Wi-Fi, Bluetooth, audio, microphone, brightness, and power-profile actions; Settings search uses the live translated/capability-aware index and exposes exact writable scalar keys instead of requiring key guesses; reversible semantic machine actions and scalar Settings writes return short-lived rollback receipts; rollback permissions are selected from the receipt kind (`device.control` vs `settings.write`);
- native installed-application search/launch through the shell launcher and exact desktop-entry IDs;
- Wayland window listing/control;
- workspace listing/activation;
- Labwc `ext-workspace-v1` state and actions.

Agents should prefer these semantic APIs over screenshots, raw input, or implementation-specific config edits.

## Built-in Assistant

The CyShell Assistant lives inside the shell UI and uses the embedded runtime. Provider/model configuration is available from **Settings → Agent**.

The Assistant supports OpenAI-compatible endpoints plus native Anthropic Messages API and native Gemini `generateContent` function calling. Gemini tool rounds preserve the original response parts so function IDs and thought signatures are replayed correctly. Endpoint/model choices are remembered per provider, conversation history survives shell restarts, and non-secret state is stored privately in the CyCom state directory. API keys are stored in the desktop Secret Service/keyring and are not written into the CyShell config.

## External MCP clients

Use `cyshell-mcp` for stdio MCP clients.

`cyshell-mcp` is only a transport adapter: it connects to the running CyShell local IPC socket and forwards MCP tool discovery/calls to the embedded CyCom registry. It does not launch a second CyCom runtime.

## Safety controls

CyShell provides persistent user-facing gates for:

- enabling/disabling the Agent runtime;
- enabling/disabling state-changing computer control;
- fine-grained capability scopes for desktop, apps, screenshots, files, system, network, remote targets, and power;
- per-app Ask/Always allow/Always deny policy for third-party app reading, control, and screenshots;
- one-shot native approval dialogs that pause the exact tool call until the user decides;
- emergency stop, which disables control and cancels active Agent calls.

The default bar exposes armed/active/pending Agent state. Left-click opens the Assistant or approval review; right-click stops control. Runtime state is event-driven over the CyShell subscription socket, including active calls, approval queue changes, permission changes, and a bounded recent tool-activity feed. The feed stores tool name, scopes, reason, caller attribution, status, timing, and compact errors but not raw tool arguments. Built-in Assistant calls are identified directly; `cyshell-mcp` forwards MCP `clientInfo` name/version for diagnostic attribution only. `dms agent open|review|status|stop|activity|receipts|undo` gives compositor-independent command targets for keyboard bindings, debugging, and rollback.

CyCom policy and audit remain active below these controls.

## Legacy compatibility bridge

`core/cmd/cyshell-agent-bridge`, `agent/cycom/cyshell-desktop-state.plugin.json`, and the old integration installer are retained only as compatibility material for standalone CyCom deployments.

They are **not** the primary CyShell Agent architecture and should not be installed when using the embedded CyShell runtime.
