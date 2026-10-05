import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Modules.CyBar
import qs.Services
import qs.Widgets

CyPopout {
    id: root

    property var currentWindow: null
    property int processId: 0

    readonly property string appId: currentWindow?.appId || ""
    readonly property string windowTitle: currentWindow?.title || ""
    readonly property string appName: appId ? Paths.getAppName(appId, DesktopEntries.heuristicLookup(Paths.moddedAppId(appId))) : I18n.tr("Unknown")
    readonly property int pid: processId
    readonly property string scratchpadName: CompositorService.windowScratchpadName(currentWindow)

    layerNamespace: "cyshell:focused-window-popout"
    popupWidth: 340
    popupHeight: contentLoader.item ? contentLoader.item.implicitHeight : 260
    triggerWidth: 40
    positioning: ""
    shouldBeVisible: false


    function testPattern(pattern, value) {
        if (!pattern)
            return true;
        try {
            return new RegExp(pattern).test(value || "");
        } catch (e) {
            return pattern === (value || "");
        }
    }

    onBackgroundClicked: close()

    content: Component {
        Rectangle {
            id: contentRoot

            implicitWidth: 340
            implicitHeight: contentColumn.implicitHeight + PopoutMetrics.contentPadding * 2
            anchors.fill: parent
            color: "transparent"
            focus: true

            Keys.onEscapePressed: event => {
                root.close();
                event.accepted = true;
            }

            Column {
                id: contentColumn
                anchors.fill: parent
                anchors.margins: PopoutMetrics.contentPadding
                spacing: Theme.spacingXXS

                Row {
                    width: parent.width
                    height: BarMetrics.menuRowHeight
                    spacing: Theme.spacingS

                    IconImage {
                        width: Theme.iconSizeMedium
                        height: Theme.iconSizeMedium
                        source: Paths.getAppIcon(root.appId, DesktopEntries.heuristicLookup(root.appId))
                        asynchronous: true
                        mipmap: true
                        smooth: true
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        width: parent.width - Theme.iconSizeMedium - Theme.spacingS
                        text: root.appName
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        clip: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Repeater {
                    model: [
                        {
                            label: I18n.tr("App ID"),
                            value: root.appId,
                            copyable: !!root.appId
                        },
                        {
                            label: I18n.tr("Title"),
                            value: root.windowTitle || I18n.tr("Untitled"),
                            copyable: !!root.windowTitle
                        },
                        {
                            label: I18n.tr("PID", "Label for the process ID row in the focused window popout"),
                            value: root.pid > 0 ? root.pid.toString() : I18n.tr("Unavailable"),
                            copyable: root.pid > 0
                        }
                    ]

                    delegate: CyListRow {
                        id: copyRow
                        required property var modelData
                        required property int index
                        readonly property real labelWidth: Theme.iconButtonSize + Theme.iconSizeLarge

                        width: contentColumn.width
                        implicitHeight: Theme.listItemHeight
                        firstInGroup: index === 0
                        lastInGroup: index === 2

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingL
                            anchors.rightMargin: Theme.spacingL
                            spacing: Theme.spacingS

                            StyledText {
                                width: copyRow.labelWidth
                                text: copyRow.modelData.label
                                color: copyRow.supportingContentColor
                                font.pixelSize: Theme.fontSizeSmall
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                width: parent.width - copyRow.labelWidth - Theme.spacingS
                                text: copyRow.modelData.value
                                color: copyRow.contentColor
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: SettingsData.monoFontFamily
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideMiddle
                                clip: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        StateLayer {
                            topLeftRadius: copyRow.firstInGroup ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
                            topRightRadius: topLeftRadius
                            bottomLeftRadius: copyRow.lastInGroup ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
                            bottomRightRadius: bottomLeftRadius
                            enabled: copyRow.modelData.copyable
                            disabled: !copyRow.modelData.copyable
                            onClicked: root.copyValue(copyRow.modelData.value)
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: Theme.dividerWidth
                    color: Theme.outlineVariant
                }

                Item {
                    visible: root.scratchpadName !== ""
                    width: parent.width
                    height: BarMetrics.menuRowHeight

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingS
                        spacing: Theme.spacingS

                        CyIcon {
                            name: "outbox"
                            size: Theme.iconSizeSmall
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: I18n.tr("Move out of scratchpad")
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    StateLayer {
                        cornerRadius: BarMetrics.menuItemRadius
                        onClicked: {
                            CompositorService.moveWindowOutOfSpecial(root.currentWindow);
                            root.close();
                        }
                    }
                }

                Repeater {
                    model: root.scratchpadName !== "" ? [] : CompositorService.specialWorkspaceNames

                    Item {
                        required property string modelData

                        width: parent.width
                        height: BarMetrics.menuRowHeight

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingS
                            spacing: Theme.spacingS

                            CyIcon {
                                name: "inbox"
                                size: Theme.iconSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: modelData === "special" ? I18n.tr("Move to scratchpad") : I18n.tr("Move to scratchpad: %1", "%1 is the named special workspace").arg(modelData)
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        StateLayer {
                            cornerRadius: BarMetrics.menuItemRadius
                            onClicked: {
                                CompositorService.moveWindowToSpecial(root.currentWindow, modelData);
                                root.close();
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: BarMetrics.menuRowHeight

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingS
                        spacing: Theme.spacingS

                        CyIcon {
                            name: "close"
                            size: Theme.iconSizeSmall
                            color: Theme.error
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: I18n.tr("Kill Process")
                            color: Theme.error
                            font.pixelSize: Theme.fontSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    StateLayer {
                        cornerRadius: BarMetrics.menuItemRadius
                        stateColor: Theme.error
                        enabled: root.pid > 0
                        disabled: root.pid <= 0
                        onClicked: root.killWindow()
                    }
                }
            }
        }
    }
}
