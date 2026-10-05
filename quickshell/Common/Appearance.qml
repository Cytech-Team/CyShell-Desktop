pragma Singleton

import Quickshell
import qs.CyCommon.Common as CyCommon

Singleton {
    readonly property var rounding: CyCommon.Appearance.rounding
    readonly property var spacing: CyCommon.Appearance.spacing
    readonly property var fontSize: CyCommon.Appearance.fontSize
    readonly property var anim: CyCommon.Appearance.anim
}
