# CyShell Desktop

<p align="center">
  <img src="quickshell/assets/cyshell.png" width="180" alt="CyShell Desktop logo">
</p>

**CyShell Desktop** is an agent-native Wayland desktop shell by **Cytech Team Development**, built for Labwc and designed around deep desktop integration, semantic control, and safe automation.

CyShell is not just a desktop UI. The shell exposes the same structured control surface to users, agents, MCP clients, and internal automation, allowing the desktop itself to act as a programmable system layer.

## Highlights

- **Agent-native desktop control** for applications, windows, workspaces, settings, and system actions.
- **Embedded CyCom runtime** with permissions, auditing, caller attribution, and emergency-stop controls.
- **Semantic desktop APIs** so agents can operate on real desktop concepts instead of fragile screen coordinates.
- **CyShell MCP bridge** for external MCP clients without spawning a second agent runtime.
- **CyShell Greeter** integrated with greetd for a native login and session experience.
- **CyStart** unified Start + Search powered by the shell launcher engine.
- **Native Labwc workspace integration** through `ext-workspace-v1`.
- **Reversible system actions** with short-lived rollback receipts where supported.
- **Integrated desktop shell features** including taskbar/panel, launcher, settings, notifications, OSD, clipboard, lock screen, session controls, and desktop services.
- **Single desktop control surface** shared between the UI, CLI, agents, and automation.
- **Primary `cyshell` CLI** with legacy `dms` compatibility retained during migration.

## Architecture

```text
CyShell Desktop
├── Quickshell UI
├── CyShell Core (Go)
├── CyCom runtime
├── cyshell-mcp
└── CyShell Greeter
```

CyShell keeps the UI, desktop services, semantic APIs, and agent runtime connected through one system instead of treating automation as an external layer bolted onto the desktop.

See [CYSHELL.md](CYSHELL.md) for architecture, compatibility policy, implementation status, and roadmap.

## Development

Build the current core:

```sh
make build
./core/bin/dms run -c ./quickshell
```

For an installed build:

```sh
cyshell run
cyshell agent status
cyshell-mcp
```

Greeter status:

```sh
cyshell-greeter status
```

## Compatibility

CyShell Desktop originally started as a fork of [AvengeMedia/DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) and has since evolved into an independently developed project by **Cytech Team Development**.

Some internal identifiers such as `Dank*` QML components, `DMSService`, legacy configuration paths, and the `dms` command/service surface are intentionally retained while migration continues. These are compatibility details, not the CyShell product identity.

## Upstream attribution

CyShell preserves the upstream license and attribution from [AvengeMedia/DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell). Upstream code and compatibility layers remain subject to their original license terms.

## Project

- Repository: [Cytech-Team/CyShell-Desktop](https://github.com/Cytech-Team/CyShell-Desktop)
- Development branch: `cyshell-dev`
- Maintained by **Cytech Team Development**
