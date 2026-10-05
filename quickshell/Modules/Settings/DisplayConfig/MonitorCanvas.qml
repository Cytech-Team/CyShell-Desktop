import QtQuick
import qs.Common
import qs.Widgets

Rectangle {
    id: root

    property string draggingOutput: ""

    readonly property var filteredOutputs: Object.keys(DisplayConfigState.allOutputs || {})
        .filter(name => {
            const output = DisplayConfigState.allOutputs[name];
            return output?.connected && !DisplayConfigState.isVirtualOutput(output);
        })

    readonly property var filteredBounds: {
        const all = DisplayConfigState.allOutputs || {};
        let minX = Infinity;
        let minY = Infinity;
        let maxX = -Infinity;
        let maxY = -Infinity;

        for (const name of filteredOutputs) {
            const output = all[name];
            if (!output?.logical || !output.enabled)
                continue;
            const size = DisplayConfigState.getLogicalSize(output);
            const x = output.logical.x ?? 0;
            const y = output.logical.y ?? 0;
            minX = Math.min(minX, x);
            minY = Math.min(minY, y);
            maxX = Math.max(maxX, x + size.w);
            maxY = Math.max(maxY, y + size.h);
        }

        if (minX === Infinity)
            return { minX: 0, minY: 0, width: 1920, height: 1080 };

        return {
            minX,
            minY,
            width: Math.max(1, maxX - minX),
            height: Math.max(1, maxY - minY)
        };
    }

    width: parent?.width ?? 0
    height: 300
    radius: Theme.cornerRadius
    color: Theme.floatingWindowNestedSurface
    border.color: Theme.outlineMedium
    border.width: Theme.layerOutlineWidth
    clip: true

    Item {
        id: canvas

        anchors.fill: parent
        anchors.margins: Theme.spacingL

        readonly property var bounds: root.filteredBounds
        readonly property real scaleFactor: {
            const padding = Theme.spacingM * 2;
            const scaleX = Math.max(0.02, (width - padding) / Math.max(1, bounds.width));
            const scaleY = Math.max(0.02, (height - padding) / Math.max(1, bounds.height));
            return Math.min(scaleX, scaleY);
        }
        readonly property point offset: Qt.point(
            (width - bounds.width * scaleFactor) / 2 - bounds.minX * scaleFactor,
            (height - bounds.height * scaleFactor) / 2 - bounds.minY * scaleFactor
        )

        Repeater {
            model: root.filteredOutputs

            delegate: MonitorRect {
                required property string modelData

                outputName: modelData
                outputData: DisplayConfigState.allOutputs[modelData]
                canvasScaleFactor: canvas.scaleFactor
                canvasOffset: canvas.offset

                onIsDraggingChanged: {
                    if (isDragging) {
                        root.draggingOutput = outputName;
                    } else if (root.draggingOutput === outputName) {
                        root.draggingOutput = "";
                    }
                }
            }
        }
    }

    StyledText {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: Theme.spacingS
        text: I18n.tr("Drag displays to rearrange them")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }
}
