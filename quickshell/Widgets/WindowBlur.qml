import QtQuick

Item {
    id: root
    visible: false

    required property var targetWindow
    property bool blurEnabled: false
    property real blurX: 0
    property real blurY: 0
    property real blurWidth: 0
    property real blurHeight: 0
    property real blurRadius: 0
    property real blurBottomRadius: blurRadius
    property bool clipEnabled: false
    property real clipX: blurX
    property real clipY: blurY
    property real clipWidth: blurWidth
    property real clipHeight: blurHeight

    readonly property bool _active: false

    function _apply() {}
    function _clear() {}
    function kick() {}
    function _scheduleLifecycleKick() {}
    function _runLifecycleKick() {}
}
