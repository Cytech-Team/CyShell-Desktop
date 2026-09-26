# CyShell Desktop

<p align="center">
  <img src="quickshell/assets/cyshell.png" width="180" alt="CyShell Desktop logo">
</p>

**CyShell Desktop** is an agent-native Wayland desktop shell by **Cytech Team Development**. It is built for Labwc first and combines a native desktop experience with semantic desktop APIs, safe automation, an embedded CyCom runtime, and a dedicated CyShell Greeter.

CyShell is both a desktop shell and the reference implementation of the CyShell framework: the desktop itself uses the same semantic control surface exposed to agents and external MCP clients.

## Highlights

- Blue-first CyShell visual identity with a matching shell and login experience.
- Native panel/taskbar, launcher, settings, notifications, OSD, clipboard, lock screen and desktop integrations.
- **CyShell Greeter** on top of greetd, using CyShell UI, theme state and its own cache path.
- **CyStart** unified Start + Search using the shell launcher engine.
- Embedded **CyCom** agent runtime with permissions, audit, caller attribution and emergency stop.
- Semantic settings, applications, windows, workspaces and machine controls.
- Reversible machine/settings actions through short-lived rollback receipts.
- Native Labwc workspace support through `ext-workspace-v1`.
- `cyshell-mcp` for external MCP clients without creating a second agent runtime.
- `cyshell` is the primary user-facing CLI; `dms` remains an implementation compatibility alias while migration continues.

## Current desktop stack

```text
greetd
└── cyshell-greeter
    └── CyShell QML / Quickshell UI
        ├── CyShell blue theme
        ├── CyShell settings + session state
        └── CyShell Greeter cache

CyShell Desktop
├── Quickshell UI
├── CyShell Core (Go)
├── CyCom runtime
└── cyshell-mcp
```

The default CyShell palette is **Blue**. In dark mode the primary color is `#42a5f5`, with `#0d47a1` as the primary container and `#8ab4f8` as the secondary accent.

## Architecture

See [CYSHELL.md](CYSHELL.md) for architecture, compatibility policy, implementation status and roadmap.

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

Greeter status can be checked with:

```sh
cyshell-greeter status
```

## Compatibility

CyShell Desktop originally started as a fork of [AvengeMedia/DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) and has since evolved into an independently developed project by **Cytech Team Development**. Some internal identifiers such as `Dank*` QML components, `DMSService`, legacy configuration paths, and the `dms` command/service surface are intentionally retained while the migration is staged.

Those are compatibility implementation details, not the CyShell product brand. New user-facing features should use CyShell naming.

The old `/var/cache/dms-greeter` path may exist as a compatibility link, while the active CyShell Greeter state lives under `/var/cache/cyshell-greeter`.

## Upstream attribution

CyShell preserves the upstream license and attribution from [AvengeMedia/DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell). Upstream code and compatibility layers remain subject to their original license terms.

## Project

- Repository: [Cytech-Team/CyShell-Desktop](https://github.com/Cytech-Team/CyShell-Desktop)
- Development branch: `cyshell-dev`
- Maintained by **Cytech Team Development**
