import QtQuick
import qs.Common
import qs.Widgets

Rectangle {
    id: root

    required property string outputName
    required property var outputData
    required property real canvasScaleFactor
    required property point canvasOffset

    property bool isDragging: false
    property point originalLogical: Qt.point(0, 0)
    property point snappedLogical: Qt.point(0, 0)
    property bool isValidPosition: true

    readonly property var logicalSize: DisplayConfigState.getLogicalSize(outputData)
    readonly property bool isPrimary: DisplayConfigState.effectivePrimaryName === outputName
    readonly property bool isVirtual: DisplayConfigState.isVirtualOutput(outputData)

    x: isDragging ? x : (outputData?.logical?.x ?? 0) * canvasScaleFactor + canvasOffset.x
    y: isDragging ? y : (outputData?.logical?.y ?? 0) * canvasScaleFactor + canvasOffset.y
    width: Math.max(72, logicalSize.w * canvasScaleFactor)
    height: Math.max(46, logicalSize.h * canvasScaleFactor)
    radius: Theme.cornerRadius
    opacity: outputData?.enabled ? 1.0 : 0.48
    z: isDragging ? 100 : 1

    color: {
        if (!isValidPosition)
            return Theme.withAlpha(Theme.error, 0.26);
        if (isDragging)
            return Theme.withAlpha(Theme.primary, 0.34);
        if (dragArea.containsMouse)
            return Theme.withAlpha(Theme.primary, 0.18);
        return Theme.floatingWindowSurface;
    }

    border.width: isPrimary || isDragging ? 3 : Theme.outlineWidthFocused
    border.color: {
        if (!isValidPosition)
            return Theme.error;
        if (isPrimary || isDragging)
            return Theme.primary;
        return Theme.outline;
    }

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 5
        visible: root.isPrimary
        width: primaryLabel.implicitWidth + 12
        height: 22
        radius: 11
        color: Theme.primary
        z: 2

        StyledText {
            id: primaryLabel
            anchors.centerIn: parent
            text: I18n.tr("Main")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.onPrimary
            font.weight: Theme.fontWeightMedium
        }
    }

    Column {
        anchors.centerIn: parent
        width: Math.max(20, parent.width - 16)
        spacing: 2

        CyIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: root.isVirtual ? "developer_board" : (root.outputData?.enabled ? "desktop_windows" : "desktop_access_disabled")
            size: Math.min(24, Math.max(14, root.height * 0.20))
            color: root.outputData?.enabled ? Theme.primary : Theme.surfaceVariantText
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            text: DisplayConfigState.getOutputDisplayName(root.outputData, root.outputName)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
            maximumLineCount: 1
            font.pixelSize: Math.max(9, Math.min(13, root.width * 0.08))
            color: Theme.surfaceText
            font.weight: Theme.fontWeightMedium
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            text: {
                const mode = DisplayConfigState.currentMode(root.outputData) || DisplayConfigState.preferredMode(root.outputData);
                if (!mode)
                    return root.outputData?.enabled ? "" : I18n.tr("Disabled");
                return mode.width + "×" + mode.height + " · " + DisplayConfigState.formatRefresh(mode.refresh);
            }
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
            font.pixelSize: Math.max(8, Math.min(11, root.width * 0.065))
            color: Theme.surfaceVariantText
        }
    }

    MouseArea {
        id: dragArea

        anchors.fill: parent
        hoverEnabled: true
        enabled: root.outputData?.enabled ?? false
        cursorShape: enabled ? (root.isDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
        drag.target: enabled ? root : null
        drag.axis: Drag.XAndYAxis
        drag.threshold: 0

        onPressed: {
            root.isDragging = true;
            root.originalLogical = Qt.point(root.outputData?.logical?.x ?? 0, root.outputData?.logical?.y ?? 0);
            root.snappedLogical = root.originalLogical;
            root.isValidPosition = true;
        }

        onPositionChanged: {
            if (!root.isDragging)
                return;

            const posX = Math.round((root.x - root.canvasOffset.x) / root.canvasScaleFactor);
            const posY = Math.round((root.y - root.canvasOffset.y) / root.canvasScaleFactor);
            const size = DisplayConfigState.getLogicalSize(root.outputData);
            const snapped = SettingsData.displaySnapToEdge
                ? DisplayConfigState.snapToEdges(root.outputName, posX, posY, size.w, size.h)
                : Qt.point(posX, posY);

            root.snappedLogical = snapped;
            root.isValidPosition = !SettingsData.displaySnapToEdge
                || !DisplayConfigState.checkOverlap(root.outputName, snapped.x, snapped.y, size.w, size.h);
        }

        onReleased: {
            if (!root.isDragging)
                return;

            root.isDragging = false;
            const finalX = root.snappedLogical.x;
            const finalY = root.snappedLogical.y;

            if (!root.isValidPosition)
                return;

            if (finalX === root.originalLogical.x && finalY === root.originalLogical.y)
                return;

            DisplayConfigState.updatePosition(root.outputName, finalX, finalY);
        }

        onCanceled: {
            root.isDragging = false;
            root.isValidPosition = true;
        }
    }
}
