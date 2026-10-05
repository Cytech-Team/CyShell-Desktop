import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    popoutWidth: 780
    popoutHeight: 590
    pillClickAction: () => root.triggerPopout()

    horizontalBarPill: Component {
        Item {
            implicitWidth: 30
            implicitHeight: 32

            CyIcon {
                anchors.centerIn: parent
                name: "view_cozy"
                size: 22
                color: Theme.widgetTextColor
            }
        }
    }

    verticalBarPill: horizontalBarPill

    popoutContent: Component {
        PopoutComponent {
            id: panel

            property string filterText: ""
            readonly property var allWindows: CompositorService.sortedToplevels || []
            readonly property var filteredWindows: {
                const q = filterText.trim().toLowerCase()
                if (!q)
                    return allWindows
                return allWindows.filter(win => {
                    const title = String(win?.title || "").toLowerCase()
                    const appId = String(win?.appId || "").toLowerCase()
                    return title.includes(q) || appId.includes(q)
                })
            }
            readonly property int columns: width >= 720 ? 3 : (width >= 480 ? 2 : 1)
            readonly property real cardGap: Theme.spacingM
            readonly property real cardWidth: Math.max(
                180,
                (contentWidth - Theme.spacingL * 2 - cardGap * (columns - 1)) / columns
            )
            readonly property real previewHeight: Math.round(cardWidth * 9 / 16)
            readonly property real cardHeight: previewHeight + 54

            headerText: "Task View"
            detailsText: filteredWindows.length + " open window" + (filteredWindows.length === 1 ? "" : "s")
            showCloseButton: true

            function activateWindow(win) {
                if (!win)
                    return
                CompositorService.activateToplevel(win)
                closePopout()
            }

            function closeWindow(win) {
                if (!win)
                    return
                win.close()
            }

            Column {
                anchors.fill: parent
                anchors.topMargin: panel.headerHeight + panel.detailsHeight
                anchors.leftMargin: Theme.spacingL
                anchors.rightMargin: Theme.spacingL
                anchors.bottomMargin: Theme.spacingL
                spacing: Theme.spacingM

                CyTextField {
                    id: searchField
                    width: parent.width
                    placeholderText: "Search open windows"
                    leftIconName: "search"
                    text: panel.filterText
                    onTextChanged: panel.filterText = text
                }

                Flickable {
                    id: scroll
                    width: parent.width
                    height: parent.height - searchField.height - parent.spacing
                    contentWidth: width
                    contentHeight: grid.implicitHeight
                    clip: true

                    Grid {
                        id: grid
                        width: scroll.width
                        columns: panel.columns
                        rowSpacing: panel.cardGap
                        columnSpacing: panel.cardGap

                        Repeater {
                            model: panel.filteredWindows

                            delegate: StyledRect {
                                id: card

                                required property var modelData

                                width: panel.cardWidth
                                height: panel.cardHeight
                                radius: Theme.cornerRadius
                                color: hoverHandler.hovered
                                    ? Theme.surfaceContainerHighest
                                    : Theme.surfaceContainerHigh
                                border.width: modelData?.activated ? 2 : 1
                                border.color: modelData?.activated
                                    ? Theme.primary
                                    : BlurService.borderColor
                                clip: true

                                Column {
                                    anchors.fill: parent

                                    ClippingRectangle {
                                        width: parent.width
                                        height: panel.previewHeight
                                        radius: Math.max(2, Theme.cornerRadius - 2)
                                        color: Theme.surface
                                        clip: true

                                        Rectangle {
                                            anchors.fill: parent
                                            color: hoverHandler.hovered
                                                ? Theme.surfaceContainerHighest
                                                : Theme.surface

                                            CyIcon {
                                                anchors.centerIn: parent
                                                name: card.modelData?.activated ? "select_window" : "crop_square"
                                                size: Math.min(parent.width, parent.height) * 0.34
                                                color: card.modelData?.activated ? Theme.primary : Theme.surfaceVariantText
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: panel.activateWindow(card.modelData)
                                        }
                                    }

                                    Item {
                                        width: parent.width
                                        height: 54

                                        Column {
                                            anchors.left: parent.left
                                            anchors.right: closeButton.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 6
                                            spacing: 2

                                            StyledText {
                                                width: parent.width
                                                text: card.modelData?.title || card.modelData?.appId || "Window"
                                                elide: Text.ElideRight
                                                color: Theme.surfaceText
                                                font.pixelSize: Theme.fontSizeMedium
                                                font.weight: card.modelData?.activated ? Font.DemiBold : Font.Normal
                                            }

                                            StyledText {
                                                width: parent.width
                                                text: card.modelData?.appId || ""
                                                elide: Text.ElideRight
                                                color: Theme.surfaceVariantText
                                                font.pixelSize: Theme.fontSizeSmall
                                            }
                                        }

                                        Rectangle {
                                            id: closeButton
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.rightMargin: 8
                                            width: 30
                                            height: 30
                                            radius: 6
                                            color: closeMouse.containsMouse ? Theme.error : "transparent"

                                            CyIcon {
                                                anchors.centerIn: parent
                                                name: "close"
                                                size: 17
                                                color: closeMouse.containsMouse ? Theme.onError : Theme.surfaceText
                                            }

                                            MouseArea {
                                                id: closeMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: panel.closeWindow(card.modelData)
                                            }
                                        }
                                    }
                                }

                                HoverHandler {
                                    id: hoverHandler
                                }
                            }
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: panel.filteredWindows.length === 0
                        text: panel.allWindows.length === 0 ? "No open windows" : "No matching windows"
                        horizontalAlignment: Text.AlignHCenter
                        color: Theme.surfaceVariantText
                    }
                }
            }

            onVisibleChanged: {
                if (visible) {
                    filterText = ""
                    Qt.callLater(() => searchField.forceActiveFocus())
                }
            }
        }
    }
}
