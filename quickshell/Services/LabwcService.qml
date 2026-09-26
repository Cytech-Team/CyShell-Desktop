pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Singleton {
    id: root

    // Exit the labwc session. Used by SessionService when the user
    // triggers logout and no custom logout command is configured.
    function quit() {
        Quickshell.execDetached(["labwc", "--exit"]);
    }

    // Reload rc.xml after Settings edits the CyShell-managed keybind block.
    // labwc --reconfigure targets the current LABWC_PID and is a no-op for
    // other compositor sessions because this service is only called on Labwc.
    function reconfigure() {
        Quickshell.execDetached(["labwc", "--reconfigure"]);
    }
}
