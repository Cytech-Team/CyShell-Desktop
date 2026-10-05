import QtQuick
import QtQuick.Layouts
import qs.Common

ColumnLayout {
    property string label: ""
    property string description: ""
    spacing: Theme.spacingXS
    Text { Layout.fillWidth: true; text: parent.label; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium; wrapMode: Text.WordWrap }
    Text { Layout.fillWidth: true; visible: text.length > 0; text: parent.description; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall; wrapMode: Text.WordWrap }
}
