import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

DankFloatingWindow {
    id: root
    readonly property var log: Log.scoped("AgentAssistantModal")
    property alias shouldBeVisible: root.visible
    property bool shouldHaveFocus: visible
    readonly property string assistantTitle: I18n.tr("CyShell Agent")

    signal closingModal

    objectName: "agentAssistantModal"
    title: assistantTitle
    minimumSize: Qt.size(Math.min(Math.round(Theme.fontSizeMedium * 34), Screen.width), Math.min(Math.round(Theme.fontSizeMedium * 32), Screen.height))
    implicitWidth: Math.min(Math.round(Theme.fontSizeMedium * 52), Screen.width)
    implicitHeight: Math.min(Math.round(Theme.fontSizeMedium * 48), Screen.height)
    visible: false

    function show() {
        visible = true;
        AgentAssistantService.refreshState();
        AgentAssistantService.loadHistory();
        Qt.callLater(() => composer.forceActiveFocus());
    }

    function hide() {
        visible = false;
    }

    function toggle() {
        if (visible)
            hide();
        else
            show();
    }

    function focusOrToggle() {
        if (!visible) {
            show();
            return;
        }
        for (const toplevel of ToplevelManager.toplevels.values) {
            if (toplevel.title !== assistantTitle && toplevel.title !== "CyShell Agent")
                continue;
            if (toplevel.activated) {
                hide();
                return;
            }
            toplevel.activate();
            return;
        }
        show();
    }

    function submit() {
        if (AgentAssistantService.send(composer.text)) {
            composer.text = "";
            Qt.callLater(() => messageList.positionViewAtEnd());
        }
    }

    onClosed: hide()
    onVisibleChanged: {
        if (!visible) {
            closingModal();
            return;
        }
        Qt.callLater(() => {
            composer.forceActiveFocus();
            messageList.positionViewAtEnd();
        });
    }

    Connections {
        target: AgentAssistantService
        function onHistoryChanged() {
            Qt.callLater(() => messageList.positionViewAtEnd());
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        DankWindowHeader {
            Layout.fillWidth: true
            controls: windowControls
            title: root.assistantTitle
            onCloseRequested: root.hide()
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: statusRow.implicitHeight + Theme.spacingM * 2
            color: Theme.surfaceContainer

            RowLayout {
                id: statusRow
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                Rectangle {
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: 4
                    color: AgentAssistantService.available && AgentControlService.enabled ? Theme.primary : Theme.error
                }

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        if (!AgentAssistantService.available)
                            return I18n.tr("Assistant backend unavailable");
                        const model = AgentAssistantService.model || I18n.tr("auto model");
                        return `${AgentAssistantService.provider} · ${model}`;
                    }
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                }

                StyledText {
                    visible: AgentAssistantService.busy
                    text: I18n.tr("Working...")
                    color: Theme.primary
                    font.pixelSize: Theme.fontSizeSmall
                }

                DankIconButton {
                    iconName: "delete_sweep"
                    tooltipText: I18n.tr("Clear conversation")
                    enabled: !AgentAssistantService.busy && AgentAssistantService.messages.length > 0
                    onClicked: AgentAssistantService.clear()
                }

                DankIconButton {
                    iconName: "front_hand"
                    tooltipText: I18n.tr("Stop Agent control")
                    iconColor: Theme.error
                    enabled: AgentControlService.available && !AgentControlService.busy
                    onClicked: AgentControlService.emergencyStop((success, error) => {
                        if (!success)
                            ToastService.showError(I18n.tr("Emergency stop failed"), error);
                    })
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledText {
                anchors.centerIn: parent
                width: Math.min(parent.width - Theme.spacingXL * 2, 440)
                visible: AgentAssistantService.messages.length === 0
                text: AgentAssistantService.lastError ? AgentAssistantService.lastError : I18n.tr("Ask CyShell to open settings, manage windows, switch workspaces, inspect the computer, or automate a task.")
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: AgentAssistantService.lastError ? Theme.error : Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeMedium
            }

            ListView {
                id: messageList
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingM
                clip: true
                model: AgentAssistantService.messages
                visible: count > 0

                delegate: Item {
                    id: messageDelegate
                    required property var modelData
                    width: ListView.view.width
                    height: bubble.height

                    readonly property bool fromUser: modelData?.role === "user"
                    readonly property bool isError: modelData?.role === "error"

                    Rectangle {
                        id: bubble
                        anchors.right: messageDelegate.fromUser ? parent.right : undefined
                        anchors.left: messageDelegate.fromUser ? undefined : parent.left
                        width: Math.max(180, parent.width * 0.82)
                        height: messageText.implicitHeight + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: messageDelegate.fromUser ? Theme.primaryContainer : (messageDelegate.isError ? Theme.errorContainer : Theme.surfaceContainerHigh)

                        StyledText {
                            id: messageText
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            text: String(messageDelegate.modelData?.content || "")
                            wrapMode: Text.Wrap
                            color: messageDelegate.fromUser ? Theme.onPrimaryContainer : (messageDelegate.isError ? Theme.onErrorContainer : Theme.surfaceText)
                            font.pixelSize: Theme.fontSizeMedium
                            textFormat: Text.PlainText
                        }
                    }
                }

                footer: Item {
                    width: messageList.width
                    height: AgentAssistantService.busy ? workingBubble.height + Theme.spacingM : 0

                    Rectangle {
                        id: workingBubble
                        visible: AgentAssistantService.busy
                        width: Math.min(parent.width * 0.6, workingText.implicitWidth + Theme.spacingL * 2)
                        height: workingText.implicitHeight + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

                        StyledText {
                            id: workingText
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            text: I18n.tr("Working on it…")
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar {}
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: composerRow.implicitHeight + Theme.spacingM * 2
            color: Theme.surfaceContainer

            RowLayout {
                id: composerRow
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                DankTextField {
                    id: composer
                    Layout.fillWidth: true
                    placeholderText: AgentControlService.enabled ? I18n.tr("Ask CyShell…") : I18n.tr("Agent runtime is disabled")
                    enabled: AgentAssistantService.available && AgentControlService.enabled && !AgentAssistantService.busy
                    onAccepted: root.submit()
                }

                DankButton {
                    text: I18n.tr("Send")
                    iconName: "send"
                    enabled: composer.enabled && composer.text.trim().length > 0
                    onClicked: root.submit()
                }
            }
        }
    }
}
