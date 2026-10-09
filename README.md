<!-- CYTECH_README_REFRESH:START -->
<div align="center">

<a href="https://github.com/Cytech-Team/CyShell-Desktop"><img width="100%" alt="CyShell Desktop banner" src="https://capsule-render.vercel.app/api?type=waving&color=0:0B1220,100:17BEBB&height=210&section=header&text=CyShell%20Desktop&fontSize=43&fontColor=ffffff&fontAlignY=36&desc=An%20agent-native%20Wayland%20shell%20for%20Labwc&descAlignY=59&descSize=16"></a>

<img alt="PROJECT: Linux Desktop" src="https://img.shields.io/badge/PROJECT-Linux%20Desktop-17BEBB?style=flat-square&labelColor=0B1220&color=17BEBB"> <img alt="STACK: Go · Quickshell" src="https://img.shields.io/badge/STACK-Go%20%C2%B7%20Quickshell-17BEBB?style=flat-square&labelColor=0B1220&color=17BEBB">

<p><strong>An agent-native Wayland shell for Labwc</strong></p>

<a href="https://github.com/Cytech-Team/CyShell-Desktop/releases">Releases</a> · <a href="https://github.com/Cytech-Team/CyShell-Desktop/issues">Issues</a> · <a href="https://github.com/Cytech-Team/CyShell-Desktop">Source</a>

</div>

<!-- CYTECH_README_REFRESH:END -->

---

<p align="center">
  <img src="quickshell/assets/cyshell.png" width="180" alt="CyShell Desktop logo">
</p>

**CyShell Desktop** is an agent-native Wayland desktop shell by **Cytech Team Development**, built exclusively for **Labwc** and designed around deep desktop integration, semantic control, and safe automation.

CyShell is not just a desktop UI. The shell exposes the same structured control surface to users, agents, MCP clients, and internal automation, allowing the desktop itself to act as a programmable system layer. CyShell intentionally targets one compositor: **Labwc**. Niri, Hyprland, Sway, Mango and other compositor compatibility layers are not supported.

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
Labwc
└── CyShell Desktop
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
./core/bin/cyshell run -c ./quickshell
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

Legacy adapters are retained only where compatibility requires them: the `dms` CLI alias, migration reads for old DMS configuration/state, and DMS/Noctalia plugin hosts. New runtime paths, services, APIs, assets, and UI components use the CyShell identity.

## Upstream attribution

CyShell preserves the upstream license and attribution from [AvengeMedia/DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell). Upstream code and compatibility layers remain subject to their original license terms.

## Project

- Repository: [Cytech-Team/CyShell-Desktop](https://github.com/Cytech-Team/CyShell-Desktop)
- Development branch: `cyshell-dev`
- Maintained by **Cytech Team Development**
