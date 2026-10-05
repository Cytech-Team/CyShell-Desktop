import QtQuick
import Quickshell.Wayland
import qs.Common

FadeOverlayWindow {
    WlrLayershell.namespace: "cyshell:fade-to-dpms"
    fadeEnabled: SettingsData.fadeToDpmsEnabled
    gracePeriod: SettingsData.fadeToDpmsGracePeriod
    overlayColor: Theme.screenOffColor
}
