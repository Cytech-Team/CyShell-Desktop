import QtQuick
import qs.Common

Text {
    property real pointSize: Theme.fontSizeMedium
    font.pointSize: pointSize
    color: Theme.surfaceText
    renderType: Text.NativeRendering
}
