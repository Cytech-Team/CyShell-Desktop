#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const root = path.resolve(import.meta.dirname, "..");
const dockPath = path.join(root, "quickshell/Modules/Dock/DockWindowPreview.qml");
const helperPath = path.join(root, "scripts/cyshell_toplevel_thumb.py");
const patchPath = path.join(root, "patches/quickshell-labwc-live-preview.patch");
const builderPath = path.join(root, "scripts/build-cyshell-quickshell.sh");
const prefix = process.env.CYSHELL_QS_PREFIX || "/opt/cyshell-quickshell";
const quickshell = fs.existsSync(path.join(prefix, "bin/qs"))
  ? path.join(prefix, "bin/qs")
  : path.join(prefix, "bin/quickshell");

function fail(message, detail = "") {
  console.error("VERIFY FAILED:", message);
  if (detail) console.error(detail);
  process.exit(1);
}

function assert(condition, message, detail = "") {
  if (!condition) fail(message, detail);
}

function run(cmd, args = [], opts = {}) {
  return spawnSync(cmd, args, {
    encoding: "utf8",
    timeout: opts.timeout ?? 10000,
    env: { ...process.env, ...(opts.env || {}) },
    cwd: opts.cwd || root,
  });
}

function out(result) {
  return String(result.stdout || "") + String(result.stderr || "");
}

function verifySource() {
  const dock = fs.readFileSync(dockPath, "utf8");

  assert(!fs.existsSync(helperPath), "obsolete screenshot thumbnail helper still exists");
  assert(dock.includes("ScreencopyView {"), "Dock preview does not use ScreencopyView");
  assert(
    dock.includes("captureSource: root.visible && card.visible ? card.modelData : null"),
    "Dock preview is not bound directly to the per-window Toplevel object",
  );
  assert(dock.includes("live: root.visible && card.visible"), "Dock preview is not configured as a live stream");

  const banned = [
    "cyshell_toplevel_thumb.py",
    "/tmp/cyshell-window-preview-",
    "previewFilePath",
    "previewRevision",
    "previewCapture",
    "file://",
  ];
  for (const token of banned)
    assert(!dock.includes(token), "screenshot/file polling residue remains in Dock preview: " + token);

  assert(!/Timer\s*\{[\s\S]{0,220}interval:\s*1200/.test(dock), "old 1.2s screenshot refresh timer remains");
  console.log("LIVE PREVIEW SOURCE VERIFY PASSED");
}

function verifyPatch() {
  assert(fs.existsSync(patchPath), "maintained Quickshell live-preview patch is missing");
  assert(fs.existsSync(builderPath), "reproducible Quickshell build script is missing");

  const patch = fs.readFileSync(patchPath, "utf8");
  const builder = fs.readFileSync(builderPath, "utf8");
  for (const token of [
    "ext_foreign_toplevel_image_capture_source_manager_v1",
    "IccToplevelSourceManager",
    "IccForeignToplevelList",
    "SCREENCOPY_ICC_TOPLEVEL",
    "wl_display_roundtrip",
    "create_source(handle->object())",
  ]) {
    assert(patch.includes(token), "Quickshell patch is missing required ICC toplevel code: " + token);
  }

  assert(builder.includes('TAG="${CYSHELL_QS_TAG:-v0.3.1}"'), "builder is not pinned to Quickshell v0.3.1");
  assert(builder.includes("CyShell-Labwc-ICC"), "builder does not stamp the CyShell ICC distributor");

  assert(fs.existsSync(quickshell), "patched Quickshell is not installed at " + quickshell);
  const version = run(quickshell, ["--version"]);
  assert(version.status === 0, "installed patched Quickshell cannot run", out(version));
  const strings = run("strings", [quickshell], { timeout: 8000 });
  assert(
    out(version).includes("CyShell-Labwc-ICC")
      || out(strings).includes("No ext-foreign-toplevel capture source matched"),
    "installed Quickshell does not contain the CyShell foreign-toplevel ICC backend",
    out(version),
  );

  console.log("QUICKSHELL ICC PATCH VERIFY PASSED");
}

function verifyRuntime() {
  const service = run("systemctl", ["--user", "is-active", "cyshell.service"]);
  assert(service.status === 0 && service.stdout.trim() === "active", "cyshell.service is not active", out(service));

  const wi = run("wayland-info", [], { timeout: 6000 });
  const protocols = out(wi);
  for (const global of [
    "ext_image_copy_capture_manager_v1",
    "ext_foreign_toplevel_image_capture_source_manager_v1",
    "ext_foreign_toplevel_list_v1",
  ]) {
    assert(protocols.includes(global), "Labwc is missing required Wayland global: " + global);
  }

  let patchedRunning = false;
  for (const entry of fs.readdirSync("/proc")) {
    if (!/^\d+$/.test(entry)) continue;
    try {
      const exe = fs.readlinkSync("/proc/" + entry + "/exe");
      if (exe.startsWith(prefix + "/bin/")) {
        const cmdline = fs.readFileSync("/proc/" + entry + "/cmdline", "utf8").replace(/\0/g, " ");
        if (cmdline.includes("CyShell-Desktop/quickshell") || cmdline.includes("-c "))
          patchedRunning = true;
      }
    } catch {}
  }
  assert(patchedRunning, "CyShell is not running with the patched Quickshell binary under " + prefix);

  console.log("LIVE PREVIEW RUNTIME VERIFY PASSED");
}

function verifyExercise() {
  assert(fs.existsSync(quickshell), "patched Quickshell is not installed");

  const probe = path.join(os.tmpdir(), "cyshell-live-window-preview-probe.qml");
  fs.writeFileSync(probe, `import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: root
    property var target: null
    property bool passed: false

    Component.onCompleted: {
        Quickshell.watchFiles = false
        chooseTarget.start()
        timeout.start()
    }

    Timer {
        id: chooseTarget
        interval: 100
        repeat: true
        onTriggered: {
            const candidate = ToplevelManager.activeToplevel
                || ((ToplevelManager.toplevels?.values?.length ?? 0) > 0 ? ToplevelManager.toplevels.values[0] : null)
            if (!candidate)
                return
            stop()
            root.target = candidate
            console.log("LIVE_CAPTURE_TARGET", candidate.appId, candidate.title)
            probeWindow.visible = true
        }
    }

    FloatingWindow {
        id: probeWindow
        visible: false
        width: 320
        height: 200
        color: "black"

        ScreencopyView {
            anchors.fill: parent
            captureSource: root.target
            live: root.target !== null
            paintCursor: false
            onHasContentChanged: {
                if (hasContent && !root.passed) {
                    root.passed = true
                    console.log("LIVE_CAPTURE_PASS", sourceSize.width, sourceSize.height)
                    Qt.callLater(Qt.quit)
                }
            }
        }
    }

    Timer {
        id: timeout
        interval: 6000
        repeat: false
        onTriggered: {
            if (!root.passed)
                console.log("LIVE_CAPTURE_FAIL timeout")
            Qt.quit()
        }
    }
}
`);

  const probeRun = run(quickshell, ["-p", probe, "--no-color", "-v"], { timeout: 8000 });
  const log = out(probeRun);
  try { fs.unlinkSync(probe); } catch {}

  assert(log.includes("LIVE_CAPTURE_PASS"), "native Toplevel ScreencopyView did not receive live content", log.slice(-5000));
  assert(!log.includes("LIVE_CAPTURE_FAIL"), "native live-capture probe reported failure", log.slice(-5000));
  assert(!log.includes("Capture source set to non captureable object"), "ScreencopyView rejected the Toplevel capture source", log.slice(-5000));

  const helpers = run("pgrep", ["-af", "cyshell_toplevel_thumb.py"]);
  assert(helpers.status !== 0 || !helpers.stdout.trim(), "obsolete screenshot helper process is running", helpers.stdout);

  console.log("LIVE PREVIEW EXERCISE PASSED");
}

switch (process.argv[2]) {
case "source":
  verifySource();
  break;
case "patch":
  verifyPatch();
  break;
case "runtime":
  verifyRuntime();
  break;
case "exercise":
  verifyExercise();
  break;
default:
  console.error("usage: node scripts/verify-live-window-preview.mjs <source|patch|runtime|exercise>");
  process.exit(2);
}
