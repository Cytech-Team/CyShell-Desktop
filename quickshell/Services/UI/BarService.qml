pragma Singleton
import QtQuick
import Quickshell
import qs.Services

Singleton {
    function getTooltipDirection(screenName) { return "bottom"; }
    function openPluginSettings(pluginId) {
        PluginService.pendingSettingsRevealPluginId = pluginId || "";
        PopoutService.openSettingsWithTab("plugins");
    }
}
