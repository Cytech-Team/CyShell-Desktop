pragma Singleton
import QtQuick
import Quickshell
import qs.Common

Singleton {
    readonly property real uiScaleRatio: 1.0
    readonly property real marginXS: Theme.spacingXS
    readonly property real marginS: Theme.spacingS
    readonly property real marginM: Theme.spacingM
    readonly property real marginL: Theme.spacingL
    readonly property real marginXL: Theme.spacingXL
    readonly property real margin2M: Theme.spacingM * 2
    readonly property real radiusS: Theme.cornerRadiusS
    readonly property real radiusM: Theme.cornerRadiusM
    readonly property real radiusL: Theme.cornerRadiusL
    readonly property real iRadiusL: Theme.cornerRadiusL
    readonly property real borderS: 1
    readonly property real borderM: 2
    readonly property real baseWidgetSize: 32
    readonly property real fontSizeXS: Math.max(10, Theme.fontSizeSmall - 2)
    readonly property real fontSizeS: Theme.fontSizeSmall
    readonly property real fontSizeM: Theme.fontSizeMedium
    readonly property real fontSizeL: Theme.fontSizeLarge
    readonly property real fontSizeXL: Theme.fontSizeXLarge
    readonly property real fontSizeXXL: Theme.fontSizeXXLarge
    readonly property int fontWeightBold: Font.Bold
    readonly property color capsuleBorderColor: Theme.outlineVariant
    readonly property real capsuleBorderWidth: 1
    readonly property color capsuleColor: Theme.surfaceContainer
    readonly property real opacityMedium: 0.60
    readonly property real opacityHeavy: 0.85
    readonly property real opacityFull: 1.0
    readonly property int animationNormal: Theme.mediumDuration

    function getCapsuleHeightForScreen(screenName) { return 32; }
    function pixelAlignCenter(v) { return Math.round(v); }
    function toOdd(v) { const n = Math.round(v); return n % 2 ? n : n + 1; }
}
