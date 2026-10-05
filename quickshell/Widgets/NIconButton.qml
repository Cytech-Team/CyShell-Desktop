import QtQuick
import qs.Common

Rectangle {
    id: root
    property string icon: ""
    property var tooltipText: ""
    property string tooltipDirection: "bottom"
    property real baseSize: 32
    property bool applyUiScale: true
    property color colorFg: Theme.surfaceText
    property real customRadius: -1
    property bool hovered: mouse.containsMouse
    signal clicked(var mouse)

    implicitWidth: baseSize
    implicitHeight: baseSize
    width: implicitWidth
    height: implicitHeight
    radius: customRadius >= 0 ? customRadius : Math.min(width, height) / 2
    color: mouse.containsMouse ? Theme.surfaceHover : "transparent"

    CyIcon {
        anchors.centerIn: parent
        name: root.icon
        size: Math.max(16, root.baseSize * 0.62)
        color: root.colorFg
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: event => root.clicked(event)
    }
}
