import QtQuick
import Quickshell.Wayland
import qs.Common

FadeOverlayWindow {
    WlrLayershell.namespace: "cyshell:fade-to-lock"
    fadeEnabled: SettingsData.fadeToLockEnabled
    gracePeriod: SettingsData.fadeToLockGracePeriod
    holdsAfterCompletion: true
}
