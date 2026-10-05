import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins

PluginComponent {
    id: root

    // State owned by this Peek button. Actual window stacking/order is owned by Labwc.
    property bool desktopShown: false
    property bool previewActive: false
    property bool previewBaseDesktopShown: false
    property bool previewArmed: true
    property bool pillHovered: false

    function nativeToggleDesktop() {
        // F24 is a private CyShell Labwc binding mapped to ToggleShowDesktop.
        // Labwc restores its own saved stacking/focus order correctly.
        Quickshell.execDetached(["/usr/bin/ydotool", "key", "194:1", "194:0"]);
    }

    function toggleDesktop() {
        previewDelay.stop();
        restoreDelay.stop();
        rearmDelay.stop();

        if (previewActive) {
            // Current visible state is the opposite of the state before preview.
            // Clicking while previewing pins what is currently visible.
            desktopShown = !previewBaseDesktopShown;
            previewActive = false;
            previewArmed = false;
            rearmDelay.restart();
            return;
        }

        nativeToggleDesktop();
        desktopShown = !desktopShown;

        // After clicking Show Desktop the pointer is already on Peek, so there
        // is no new hover-enter event. Explicitly arm reverse preview.
        if (desktopShown && pillHovered && previewArmed)
            previewDelay.restart();
    }

    function beginPreview() {
        if (!previewArmed || previewActive)
            return;

        previewBaseDesktopShown = desktopShown;
        previewActive = true;
        previewArmed = false;
        nativeToggleDesktop();
    }

    function endPreview() {
        if (!previewActive)
            return;

        // Return to the exact Labwc state that existed before the preview.
        nativeToggleDesktop();
        previewActive = false;
    }

    pillClickAction: () => root.toggleDesktop()

    pillHoverAction: () => {
        root.pillHovered = true;
        restoreDelay.stop();
        if (root.previewArmed)
            previewDelay.restart();
    }

    pillHoverLeaveAction: () => {
        root.pillHovered = false;
        previewDelay.stop();
        if (root.previewActive)
            restoreDelay.restart();
        rearmDelay.restart();
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: 8
            implicitHeight: Math.max(root.barThickness || 40, 40)

            Rectangle {
                width: 2
                height: parent.height
                anchors.right: parent.right
                color: (root.previewActive || root.desktopShown)
                    ? Theme.withAlpha(Theme.surfaceText, 0.12)
                    : Theme.withAlpha(Theme.surfaceText, 0.035)
                border.width: 1
                border.color: (root.previewActive || root.desktopShown)
                    ? Theme.withAlpha(Theme.surfaceText, 0.35)
                    : Theme.outline
            }

        }
    }

    verticalBarPill: horizontalBarPill

    Timer {
        id: previewDelay
        interval: 450
        repeat: false
        onTriggered: root.beginPreview()
    }

    Timer {
        id: restoreDelay
        interval: 160
        repeat: false
        onTriggered: root.endPreview()
    }

    Timer {
        id: rearmDelay
        interval: 300
        repeat: false
        onTriggered: root.previewArmed = true
    }
}
