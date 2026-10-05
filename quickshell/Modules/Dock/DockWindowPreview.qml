pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

PanelWindow {
    id: root

    property var targetScreen: null
    property var anchorItem: null
    property var surfaceContext: null
    property var options: ({})
    property var windows: []
    property var pendingAnchor: null
    property var pendingScreen: null
    property var pendingOptions: ({})
    property point anchorPos: Qt.point(0, 0)

    readonly property int windowCount: windows?.length ?? 0
    readonly property bool isVertical: options.position === SettingsData.Position.Left || options.position === SettingsData.Position.Right
    readonly property real outerPadding: Theme.spacingS
    readonly property real cardSpacing: Theme.spacingS
    readonly property real cardWidth: 260
    readonly property real cardHeight: 184
    readonly property int maxColumns: {
        const width = targetScreen?.width ?? Screen.width;
        return Math.max(1, Math.floor((Math.max(1, width - Theme.spacingM * 2) - outerPadding * 2 + cardSpacing) / (cardWidth + cardSpacing)));
    }
    readonly property int previewColumns: Math.max(1, Math.min(windowCount, maxColumns))
    // Labwc exposes live toplevel capture through the patched Quickshell ICC backend.
    readonly property bool supportsToplevelCapture: CompositorService.isHyprland || (CompositorService.isLabwc && Quickshell.env("CYSHELL_QS_ICC_TOPLEVEL_CAPTURE") === "1")
    readonly property bool hovered: previewHover.hovered
    readonly property bool interactionActive: visible || showTimer.running || hideTimer.running

    readonly property string appIconSource: {
        const button = anchorItem;
        if (!button?.appData?.appId)
            return "";
        return Paths.getAppIcon(button.appData.appId, button.cachedDesktopEntry);
    }

    function previewWindowsFor(button) {
        if (!button?.getPreviewToplevels)
            return [];
        const list = button.getPreviewToplevels();
        return Array.isArray(list) ? list.filter(t => t !== null && t !== undefined) : [];
    }

    function scheduleShow(button, screen, previewOptions) {
        const list = previewWindowsFor(button);
        if (!button || list.length === 0) {
            scheduleHide();
            return false;
        }

        pendingAnchor = button;
        pendingScreen = screen ?? null;
        pendingOptions = previewOptions ?? ({});
        hideTimer.stop();
        showTimer.interval = visible ? 80 : 320;
        showTimer.restart();
        return true;
    }

    function showNow() {
        const button = pendingAnchor;
        if (!button)
            return;

        const list = previewWindowsFor(button);
        if (list.length === 0) {
            forceHide();
            return;
        }

        anchorItem = button;
        targetScreen = pendingScreen;
        surfaceContext = button?.dockApps?.surfaceContext ?? null;
        options = pendingOptions ?? ({});
        windows = list.slice();
        pendingAnchor = null;
        pendingScreen = null;
        pendingOptions = ({});
        updatePosition();
        visible = true;
    }

    function scheduleHide() {
        pendingAnchor = null;
        pendingScreen = null;
        pendingOptions = ({});
        showTimer.stop();
        if (!visible)
            return;
        hideTimer.restart();
    }

    function forceHide() {
        showTimer.stop();
        hideTimer.stop();
        pendingAnchor = null;
        pendingScreen = null;
        pendingOptions = ({});
        visible = false;
        windows = [];
        anchorItem = null;
        surfaceContext = null;
    }

    function refreshWindows() {
        if (!visible || !anchorItem)
            return;
        const list = previewWindowsFor(anchorItem);
        if (list.length === 0) {
            forceHide();
            return;
        }
        windows = list.slice();
        updatePosition();
    }

    function updatePosition() {
        if (!anchorItem || !targetScreen)
            return;

        const point = surfaceContext?.screenPoint(anchorItem, anchorItem.width / 2, anchorItem.height / 2);
        if (!point)
            return;

        const extent = (surfaceContext?.thickness ?? (isVertical ? anchorItem.width : anchorItem.height)) / 2 + Theme.spacingS;
        switch (options.position) {
        case SettingsData.Position.Left:
            anchorPos = Qt.point(point.x + extent, point.y);
            break;
        case SettingsData.Position.Right:
            anchorPos = Qt.point(point.x - extent, point.y);
            break;
        case SettingsData.Position.Top:
            anchorPos = Qt.point(point.x, point.y + extent);
            break;
        default:
            anchorPos = Qt.point(point.x, point.y - extent);
            break;
        }
    }

    function activateToplevel(toplevel) {
        if (!toplevel)
            return;
        if (anchorItem?.activatePreviewToplevel)
            anchorItem.activatePreviewToplevel(toplevel);
        else
            CompositorService.activateToplevel(toplevel);
        forceHide();
    }

    function closeToplevel(toplevel) {
        if (!toplevel)
            return;

        // Drop the live capture delegate before the compositor destroys the
        // toplevel. Otherwise ICC screencopy can still have a frame in flight
        // against a window that has already changed/disappeared.
        windows = (windows || []).filter(candidate => candidate !== toplevel);
        if (windows.length === 0) {
            visible = false;
            anchorItem = null;
            surfaceContext = null;
        } else {
            Qt.callLater(() => updatePosition());
        }
        Qt.callLater(() => toplevel.close());
    }

    Timer {
        id: showTimer
        repeat: false
        interval: 320
        onTriggered: root.showNow()
    }

    Timer {
        id: hideTimer
        repeat: false
        interval: 220
        onTriggered: {
            if (!root.hovered && root.pendingAnchor === null)
                root.forceHide();
        }
    }

    Connections {
        target: CompositorService

        function onToplevelsChanged() {
            if (root.visible)
                Qt.callLater(() => root.refreshWindows());
        }
    }

    onAnchorItemChanged: {
        if (anchorItem)
            Qt.callLater(() => updatePosition());
    }
    onTargetScreenChanged: {
        if (visible)
            Qt.callLater(() => updatePosition());
    }
    onVisibleChanged: {
        if (!visible) {
            windows = [];
            anchorItem = null;
            surfaceContext = null;
        } else {
            Qt.callLater(() => updatePosition());
        }
    }

    screen: targetScreen
    implicitWidth: previewSurface.implicitWidth
    implicitHeight: previewSurface.implicitHeight
    color: "transparent"
    visible: false

    WlrLayershell.namespace: "cyshell:dock-window-preview"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        left: true
    }

    margins {
        left: {
            const width = targetScreen?.width ?? Screen.width;
            const minimum = Theme.spacingS;
            const maximum = Math.max(minimum, width - root.implicitWidth - Theme.spacingS);
            let desired = anchorPos.x - root.implicitWidth / 2;

            if (root.isVertical) {
                if (options.position === SettingsData.Position.Right)
                    desired = anchorPos.x - root.implicitWidth;
                else
                    desired = anchorPos.x;
            }

            return Math.round(Math.max(minimum, Math.min(maximum, desired)));
        }

        top: {
            const height = targetScreen?.height ?? Screen.height;
            const minimum = Theme.spacingS;
            const maximum = Math.max(minimum, height - root.implicitHeight - Theme.spacingS);
            let desired = anchorPos.y - root.implicitHeight / 2;

            if (!root.isVertical) {
                if (options.position === SettingsData.Position.Bottom)
                    desired = anchorPos.y - root.implicitHeight;
                else
                    desired = anchorPos.y;
            }

            return Math.round(Math.max(minimum, Math.min(maximum, desired)));
        }
    }

    WindowBlur {
        targetWindow: root
        blurEnabled: true
        blurX: 0
        blurY: 0
        blurWidth: root.visible ? previewSurface.width : 0
        blurHeight: root.visible ? previewSurface.height : 0
        blurRadius: previewSurface.radius
    }

    HoverHandler {
        id: previewHover

        onHoveredChanged: {
            if (hovered) {
                hideTimer.stop();
            } else if (root.pendingAnchor === null) {
                root.scheduleHide();
            }
        }
    }

    Rectangle {
        id: previewSurface

        implicitWidth: previewGrid.implicitWidth + root.outerPadding * 2
        implicitHeight: previewGrid.implicitHeight + root.outerPadding * 2
        width: implicitWidth
        height: implicitHeight
        radius: Theme.windowRadius
        color: Theme.withAlpha(Theme.floatingSurface, 0.96)
        border.color: BlurService.borderColor
        border.width: BlurService.borderWidth
        clip: true

        Grid {
            id: previewGrid

            anchors.centerIn: parent
            columns: root.previewColumns
            spacing: root.cardSpacing

            Repeater {
                model: root.windows

                delegate: Rectangle {
                    id: card

                    required property var modelData
                    required property int index
                    width: root.cardWidth
                    height: root.cardHeight
                    radius: Theme.cornerRadiusM
                    color: cardMouse.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer
                    border.width: modelData?.activated ? Math.max(2, Theme.dividerWidth) : Theme.dividerWidth
                    border.color: modelData?.activated ? Theme.primary : Theme.outlineVariant
                    clip: true

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.shortDuration
                        }
                    }

                    MouseArea {
                        id: cardMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton
                        onClicked: root.activateToplevel(card.modelData)
                    }

                    Item {
                        id: header

                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 36
                        z: 2

                        IconImage {
                            id: appIcon

                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            implicitSize: 18
                            source: root.appIconSource
                            visible: source !== "" && status === Image.Ready
                            asynchronous: true
                            mipmap: true
                            smooth: true
                        }

                        CyIcon {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            name: "web_asset"
                            size: 18
                            color: Theme.surfaceTextSecondary
                            visible: !appIcon.visible
                        }

                        StyledText {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingS + 26
                            anchors.right: closeButton.left
                            anchors.rightMargin: Theme.spacingXS
                            anchors.verticalCenter: parent.verticalCenter
                            text: card.modelData?.title || root.anchorItem?.tooltipText || ""
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Theme.fontWeightMedium
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        Rectangle {
                            id: closeButton

                            width: 28
                            height: 28
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            radius: Theme.fullRadius(width, height)
                            color: closeMouse.containsMouse ? Theme.errorContainer : "transparent"
                            z: 3

                            CyIcon {
                                anchors.centerIn: parent
                                name: "close"
                                size: 17
                                color: closeMouse.containsMouse ? Theme.onErrorContainer : Theme.surfaceText
                            }

                            MouseArea {
                                id: closeMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton
                                onClicked: mouse => {
                                    mouse.accepted = true;
                                    root.closeToplevel(card.modelData);
                                }
                            }
                        }
                    }

                    ClippingRectangle {
                        id: previewClip

                        anchors.top: header.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Theme.spacingXS
                        anchors.topMargin: 0
                        radius: Theme.cornerRadiusS
                        color: Theme.surfaceContainerLowest

                        ScreencopyView {
                            id: livePreview

                            readonly property real sourceAspect: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 1
                            readonly property real targetAspect: parent.height > 0 ? parent.width / parent.height : 1

                            anchors.centerIn: parent
                            width: hasContent
                                ? (targetAspect > sourceAspect ? parent.height * sourceAspect : parent.width)
                                : parent.width
                            height: hasContent
                                ? (targetAspect > sourceAspect ? parent.height : parent.width / sourceAspect)
                                : parent.height
                            captureSource: root.supportsToplevelCapture && root.visible && card.visible ? card.modelData : null
                            live: root.supportsToplevelCapture && root.visible && card.visible
                            paintCursor: false
                            visible: hasContent
                        }

                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 44
                            source: root.appIconSource
                            visible: !livePreview.hasContent && source !== ""
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: cardMouse.pressed ? Theme.withAlpha(Theme.onSurface, Theme.stateLayerPressed) : cardMouse.containsMouse ? Theme.withAlpha(Theme.onSurface, Theme.stateLayerHover) : "transparent"
                        }
                    }
                }
            }
        }
    }
}
