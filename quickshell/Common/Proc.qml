pragma Singleton

import Quickshell
import qs.CyCommon.Common as CyCommon

Singleton {
    readonly property int noTimeout: CyCommon.Proc.noTimeout
    readonly property string cyshellBin: CyCommon.Proc.cyshellBin

    function runCommand(id, command, callback, debounceMs, timeoutMs, owner) {
        CyCommon.Proc.runCommand(id, command, callback, debounceMs, timeoutMs, owner);
    }

    function release(id) {
        CyCommon.Proc.release(id);
    }
}
