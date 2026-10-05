import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

CyFloatingWindow {
    id: root

    readonly property var approval: AgentApprovalService.currentApproval
    readonly property int pendingCount: AgentApprovalService.pendingCount
    property bool decisionInFlight: false
    property bool decisionMadeForCurrent: false
    property string approvalId: String(approval?.id || "")

    objectName: "agentApprovalModal"
    title: I18n.tr("Agent permission")
    readonly property int modalWidth: Math.min(520, screen?.width ?? 520)
    readonly property int modalHeight: Math.min(420, screen?.height ?? 420)

    // Labwc may map a FloatingWindow at Qt's tiny fallback size before
    // minimumSize is applied. Give the surface its real size up front.
    width: modalWidth
    height: modalHeight
    minimumSize: Qt.size(modalWidth, modalHeight)
    maximumSize: minimumSize
    visible: false

    signal closingModal

    function requestTitle() {
        const scopes = approval?.scopes || [];
        const target = approval?.appName || I18n.tr("this application");
        if (scopes.includes("app.control"))
            return I18n.tr("Let Agent control %1?", "agent approval app name").arg(target);
        if (scopes.includes("screen.capture"))
            return I18n.tr("Let Agent view %1?", "agent approval app name").arg(target);
        if (scopes.includes("app.read"))
            return I18n.tr("Let Agent read %1?", "agent approval app name").arg(target);
        if (scopes.includes("files.write"))
            return I18n.tr("Allow Agent to change files?");
        if (scopes.includes("system.control"))
            return I18n.tr("Allow Agent to run a system action?");
        if (scopes.includes("remote.control"))
            return I18n.tr("Allow Agent to control a remote target?");
        if (scopes.includes("power.control"))
            return I18n.tr("Allow Agent to change the power or session state?");
        if (scopes.includes("network.access"))
            return I18n.tr("Allow Agent to access the network?");
        return I18n.tr("Allow this Agent action?");
    }

    function requestSummary() {
        const scopes = approval?.scopes || [];
        const labels = scopes.map(scope => AgentApprovalService.scopeLabel(String(scope)));
        if (labels.length === 0)
            return I18n.tr("The Agent needs access to continue your request.");
        return labels.join(" · ");
    }

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

                CyIcon {
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
                    text: root.requestTitle()
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.pendingCount > 1
                        ? I18n.tr("%1 permission requests are waiting.", "agent pending approval count").arg(root.pendingCount)
                        : I18n.tr("Choose whether to allow this action once, for this session, or remember access when available.")
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
                    text: I18n.tr("Requested access")
                    color: Theme.surfaceText
                    font.weight: Font.DemiBold
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.requestSummary()
                    color: Theme.surfaceText
                    wrapMode: Text.WordWrap
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
                    text: root.approval?.canRemember === true
                        ? I18n.tr("Remembered application access can be changed later in Settings → Agent → Application permissions.")
                        : I18n.tr("Session access expires when CyShell Agent restarts.")
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                }
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS

            CyButton {
                Layout.fillWidth: true
                text: I18n.tr("Deny")
                iconName: "block"
                enabled: !root.decisionInFlight
                onClicked: root.decide("deny_once")
            }

            CyButton {
                Layout.fillWidth: true
                text: I18n.tr("Allow for session")
                iconName: "schedule"
                enabled: !root.decisionInFlight
                onClicked: root.decide("allow_session")
            }

            CyButton {
                Layout.fillWidth: true
                visible: root.approval?.canRemember === true
                text: I18n.tr("Always allow")
                iconName: "verified_user"
                enabled: !root.decisionInFlight
                onClicked: root.decide("allow_always")
            }
        }
    }
}
