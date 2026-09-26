import QtQuick
import QtTest

Item {
    id: scene
    width: 240
    height: 100

    property int leftPresses: 0
    property int rightPresses: 0
    property int childPresses: 0
    property bool hovered: false

    // Mirrors BarPill's visual-only state layer: it may track hover, but it
    // must never own a mouse button.
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }
    }

    HoverHandler {
        id: hoverHandler
        onHoveredChanged: scene.hovered = hovered
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onPressedChanged: {
            if (pressed)
                scene.leftPresses++
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onPressedChanged: {
            if (pressed)
                scene.rightPresses++
        }
    }

    // Complex widgets such as tray/app/media controls intentionally keep
    // child-owned input. A child that accepts a button must win over the
    // surface-level TapHandler.
    Item {
        id: childControl
        x: 160
        width: 80
        height: parent.height
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onPressed: scene.childPresses++
        }
    }

    TestCase {
        name: "NativeBarInput"
        when: windowShown

        function init() {
            scene.leftPresses = 0
            scene.rightPresses = 0
            scene.childPresses = 0
        }

        function test_surfaceLeftAndRightSurviveVisualLayer() {
            mouseClick(scene, 60, 50, Qt.LeftButton)
            compare(scene.leftPresses, 1)
            compare(scene.rightPresses, 0)

            mouseClick(scene, 60, 50, Qt.RightButton)
            compare(scene.leftPresses, 1)
            compare(scene.rightPresses, 1)
        }

        function test_childControlOwnsAcceptedButton() {
            mouseClick(scene, 200, 50, Qt.LeftButton)
            compare(scene.childPresses, 1)
            compare(scene.leftPresses, 0)
        }

        function test_hoverHandlerTracksSurface() {
            mouseMove(scene, 80, 50)
            tryCompare(scene, "hovered", true)
        }
    }
}
