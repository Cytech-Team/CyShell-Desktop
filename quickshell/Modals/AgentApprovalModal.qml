import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

DankFloatingWindow {
    id: root

    readonly property var approval: AgentApprovalService.currentApproval
    readonly property int pendingCount: AgentApprovalService.pendingCount
    property bool decisionInFlight: false
    property bool decisionMadeForCurrent: false
    property string approvalId: String(approval?.id || "")

    objectName: "agentApprovalModal"
    title: I18n.tr("Agent permission")
    minimumSize: Qt.size(Math.min(520, screen?.width ?? 520), Math.min(420, screen?.height ?? 420))
    maximumSize: minimumSize
    visible: false

    signal closingModal

    function show() {
        if (!approval)
            return;
        visible = true;
    }

    function hide() {
        visible = false;
    }

    function decide(decision) {
        if (!approval || decisionInFlight || decisionMadeForCurrent)
            return;
        decisionInFlight = true;
        decisionMadeForCurrent = true;
        AgentApprovalService.respond(decision, (success, error) => {
            decisionInFlight = false;
            if (!success) {
                root.decisionMadeForCurrent = false;
                ToastService.showError(I18n.tr("Agent permission failed"), error);
                return;
            }
            // AgentApprovalService refreshes the queue and drives modal visibility.
        });
    }

    onApprovalIdChanged: {
        decisionMadeForCurrent = false;
        decisionInFlight = false;
    }

    onClosed: {
        if (approval && !decisionInFlight && !decisionMadeForCurrent)
            decide("deny_once");
        closingModal();
    }

    Connections {
        target: AgentApprovalService
        function onPendingChanged() {
            if (AgentApprovalService.pendingCount > 0) {
                root.show();
            } else {
                root.hide();
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingL
        spacing: Theme.spacingL

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingM

            Rectangle {
                Layout.preferredWidth: 52
                Layout.preferredHeight: 52
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.warning, 0.14)

                DankIcon {
                    anchors.centerIn: parent
                    name: "shield_question"
                    size: Theme.iconSizeLarge
                    color: Theme.warning
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingXS

                StyledText {
                    Layout.fillWidth: true
                    text: I18n.tr("Allow Agent access to %1?", "agent approval app name").arg(root.approval?.appName || I18n.tr("this application"))
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.pendingCount > 1 ? I18n.tr("%1 permission requests are waiting", "agent pending approval count").arg(root.pendingCount) : I18n.tr("The request is paused until you decide")
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: details.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            ColumnLayout {
                id: details
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                StyledText {
                    Layout.fillWidth: true
                    text: I18n.tr("Requested capabilities")
                    color: Theme.surfaceText
                    font.weight: Font.DemiBold
                }

                Repeater {
                    model: root.approval?.scopes || []
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Theme.spacingS

                        DankIcon {
                            name: "check_circle"
                            size: Theme.iconSizeSmall
                            color: Theme.primary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: AgentApprovalService.scopeLabel(String(modelData))
                            color: Theme.surfaceText
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: String(root.approval?.reason || "").length > 0
                    text: I18n.tr("Reason: %1", "agent approval reason").arg(String(root.approval?.reason || ""))
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    text: I18n.tr("Tool: %1", "agent approval tool name").arg(String(root.approval?.tool || ""))
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WrapAnywhere
                }
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS

            DankButton {
                Layout.fillWidth: true
                text: I18n.tr("Deny")
                iconName: "block"
                enabled: !root.decisionInFlight
                onClicked: root.decide("deny_once")
            }

            DankButton {
                Layout.fillWidth: true
                text: I18n.tr("Allow once")
                iconName: "check"
                enabled: !root.decisionInFlight
                onClicked: root.decide("allow_once")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.approval?.canRemember === true
            spacing: Theme.spacingS

            DankButton {
                Layout.fillWidth: true
                text: I18n.tr("Always deny")
                iconName: "do_not_disturb_on"
                enabled: !root.decisionInFlight
                onClicked: root.decide("deny_always")
            }

            DankButton {
                Layout.fillWidth: true
                text: I18n.tr("Always allow")
                iconName: "verified_user"
                enabled: !root.decisionInFlight
                onClicked: root.decide("allow_always")
            }
        }
    }
}
