import QtQuick

// Compatibility name used by existing DMS plugins. CyShell's current static
// artwork widget is MediaArtwork; keep the old properties plugins bind to.
Item {
    id: root

    property var activePlayer: null
    property string artUrl: ""

    MediaArtwork {
        anchors.fill: parent
        artUrl: root.artUrl
    }
}
