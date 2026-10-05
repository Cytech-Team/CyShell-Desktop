import QtQuick
import qs.Widgets
import "../../../Common/QmlUtils.js" as QmlUtils

CyReorderList {
    id: root

    readonly property bool isSettingsRow: true
    readonly property bool transparentSlot: true
    Component.onCompleted: flickable = QmlUtils.findParentFlickable(root.parent)
}
