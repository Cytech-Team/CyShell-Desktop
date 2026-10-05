pragma Singleton
import QtQuick
import Quickshell

Singleton {
    function showContextMenu(...args) { console.debug("Noctalia PanelService.showContextMenu compatibility stub"); }
    function closeContextMenu(...args) {}
    function getPanel(...args) { return null; }
}
