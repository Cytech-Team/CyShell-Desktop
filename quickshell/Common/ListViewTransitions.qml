pragma Singleton

import QtQuick
import Quickshell
import qs.CyCommon.Common as CyCommon

Singleton {
    readonly property bool enabled: CyCommon.ListViewTransitions.enabled
    readonly property Transition add: CyCommon.ListViewTransitions.add
    readonly property Transition remove: CyCommon.ListViewTransitions.remove
    readonly property Transition displaced: CyCommon.ListViewTransitions.displaced
    readonly property Transition move: CyCommon.ListViewTransitions.move
}
