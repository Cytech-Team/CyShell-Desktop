import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

BasePill {
    id: root

    section: "right"
    property var widgetData: null

    readonly property bool agentAvailable: AgentControlService.available
    readonly property bool agentEnabled: AgentControlService.enabled
    readonly property bool controlEnabled: AgentControlService.controlEnabled
    readonly property int activeCalls: AgentControlService.activeCalls
    readonly property int pendingApprovals: AgentApprovalService.pendingCount
    readonly property bool urgent: pendingApprovals > 0
    readonly property bool active: activeCalls > 0

    readonly property color agentColor: {
        if (!agentAvailable || !agentEnabled)
            return Theme.surfaceVariantText;
        if (urgent)
            return Theme.warning;
        if (active)
            return Theme.primary;
        if (controlEnabled)
            return Theme.success;
        return Theme.surfaceVariantText;
    }

    content: Component {
        Item {
            implicitWidth: root.pendingApprovals > 0 ? icon.width + badge.width + Theme.spacingXS : icon.width
            implicitHeight: root.contentThickness

            DankIcon {
                id: icon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                name: root.urgent ? "shield_question" : (root.active ? "smart_toy" : (root.controlEnabled ? "verified_user" : "smart_toy"))
                size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                color: root.agentColor
                filled: root.active || root.urgent
            }

            Rectangle {
                id: badge
                anchors.left: icon.right
                anchors.leftMargin: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                visible: root.pendingApprovals > 0
                implicitWidth: Math.max(18, badgeText.implicitWidth + Theme.spacingXS * 2)
                implicitHeight: 18
                radius: Theme.cornerRadiusFull
                color: Theme.warning

                StyledText {
                    id: badgeText
                    anchors.centerIn: parent
                    text: String(root.pendingApprovals)
                    color: Theme.background
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                }
            }

            Rectangle {
                width: 7
                height: 7
                radius: 4
                anchors.right: icon.right
                anchors.top: icon.top
                anchors.rightMargin: -2
                anchors.topMargin: -2
                color: root.urgent ? Theme.warning : (root.active ? Theme.primary : Theme.success)
                visible: root.agentEnabled && (root.controlEnabled || root.active || root.urgent)
            }
        }
    }

    onClicked: {
        if (root.pendingApprovals > 0)
            PopoutService.showAgentApproval();
        else
            PopoutService.showAgentAssistant();
    }

    onRightClicked: {
        if (!AgentControlService.available)
            return;
        AgentControlService.emergencyStop((success, error) => {
            if (!success)
                ToastService.showError(I18n.tr("Emergency stop failed"), error);
            else
                ToastService.showInfo(I18n.tr("Agent control stopped"));
        });
    }

    Rectangle {
        id: tooltip
        width: tooltipText.contentWidth + Theme.spacingM * 2
        height: tooltipText.contentHeight + Theme.spacingS * 2
        radius: Theme.cornerRadius
        color: Theme.readableSurface
        border.color: Theme.outlineMedium
        border.width: 1
        opacity: root.isMouseHovered ? 1 : 0
        visible: opacity > 0
        z: 100
        x: (parent.width - width) / 2
        y: -height - Theme.spacingXS

        StyledText {
            id: tooltipText
            anchors.centerIn: parent
            text: {
                if (!root.agentAvailable)
                    return I18n.tr("CyShell Agent unavailable");
                if (!root.agentEnabled)
                    return I18n.tr("CyShell Agent disabled");
                if (root.pendingApprovals > 0)
                    return I18n.tr("%1 Agent permissions waiting · click to review · right-click to stop", "agent bar pending approvals").arg(root.pendingApprovals);
                if (root.active) {
                    const tool = String(AgentControlService.lastActivity?.tool || "");
                    const origin = String(AgentControlService.lastActivity?.origin?.name || "");
                    if (tool && origin)
                        return I18n.tr("Agent active: %1 · %2 · right-click to stop control", "agent bar tooltip; %1 is active tool name, %2 is the calling Assistant/MCP client").arg(tool).arg(origin);
                    return tool ? I18n.tr("Agent active: %1 · right-click to stop control", "agent bar tooltip; %1 is active tool name").arg(tool) : I18n.tr("Agent active · right-click to stop control");
                }
                if (root.controlEnabled)
                    return I18n.tr("Agent control armed · right-click to stop");
                return I18n.tr("Agent read-only · click to open");
            }
            font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
            color: Theme.surfaceText
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Theme.standardEasing
            }
        }
    }
}
