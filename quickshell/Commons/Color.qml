pragma Singleton
import QtQuick
import Quickshell
import qs.Common

Singleton {
    readonly property color mPrimary: Theme.primary
    readonly property color mOnPrimary: Theme.primaryText
    readonly property color mSecondaryContainer: Theme.secondaryContainer
    readonly property color mSurface: Theme.surface
    readonly property color mSurfaceVariant: Theme.surfaceVariant
    readonly property color mOnSurface: Theme.surfaceText
    readonly property color mOnSurfaceVariant: Theme.surfaceVariantText
    readonly property color mOutline: Theme.outline
    readonly property color mHover: Theme.surfaceHover
    readonly property color mOnHover: Theme.surfaceText

    function resolveColorKey(key) {
        const map = {
            "mPrimary": mPrimary,
            "mOnPrimary": mOnPrimary,
            "mSecondaryContainer": mSecondaryContainer,
            "mSurface": mSurface,
            "mSurfaceVariant": mSurfaceVariant,
            "mOnSurface": mOnSurface,
            "mOnSurfaceVariant": mOnSurfaceVariant,
            "mOutline": mOutline,
            "mHover": mHover,
            "mOnHover": mOnHover
        };
        return map[key] ?? Theme.primary;
    }
    function smartAlpha(c, alpha) { return Qt.rgba(c.r, c.g, c.b, alpha); }
}
