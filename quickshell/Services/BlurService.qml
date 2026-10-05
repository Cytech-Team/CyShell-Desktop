pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common

Singleton {
    id: root

    // CyShell targets Labwc only. Labwc does not expose ext-background-effect-v1,
    // so compositor background blur is intentionally unavailable.
    readonly property bool compositorSupported: false
    readonly property bool available: false
    readonly property bool enabled: false

    // Keep the historical border settings because surface chrome still uses them.
    readonly property color borderColor: {
        if (!(SettingsData.blurBorderEnabled ?? true))
            return "transparent";
        const opacity = SettingsData.blurBorderOpacity ?? 0.35;
        switch (SettingsData.blurBorderColor ?? "outline") {
        case "primary":
            return Theme.withAlpha(Theme.primary, opacity);
        case "secondary":
            return Theme.withAlpha(Theme.secondary, opacity);
        case "surfaceText":
            return Theme.withAlpha(Theme.surfaceText, opacity);
        case "custom":
            return Theme.withAlpha(Qt.color(SettingsData.blurBorderCustomColor ?? "#ffffff"), opacity);
        default:
            return Theme.withAlpha(Theme.outline, opacity);
        }
    }
    readonly property int borderWidth: (SettingsData.blurBorderEnabled ?? true) ? 1 : 0

    function hoverColor(baseColor, hoverAlpha) {
        return baseColor;
    }

    Binding {
        target: Theme
        property: "blurLayersActive"
        value: false
    }
}
