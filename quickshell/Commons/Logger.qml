pragma Singleton
import QtQuick
import Quickshell

Singleton {
    function d(tag, ...args) { console.debug("[NoctaliaCompat:" + tag + "]", ...args); }
    function i(tag, ...args) { console.info("[NoctaliaCompat:" + tag + "]", ...args); }
    function w(tag, ...args) { console.warn("[NoctaliaCompat:" + tag + "]", ...args); }
    function e(tag, ...args) { console.error("[NoctaliaCompat:" + tag + "]", ...args); }
}
