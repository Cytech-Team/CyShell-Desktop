import QtQuick
import qs.Common
import qs.Services
import qs.Modules.ControlCenter.Widgets
import qs.Modules.ControlCenter.Details
import qs.Modules.Plugins

PluginComponent {
    id: root

    Ref {
        service: CyNetworkService
    }

    readonly property bool vpnActivating: CyNetworkService.vpnIsBusy || CyNetworkService.activeState === "activating"
    readonly property bool vpnActivated: CyNetworkService.connected && CyNetworkService.activeState === "activated"

    ccWidgetIcon: "vpn_key"
    ccWidgetPrimaryText: I18n.tr("VPN", "virtual private network, widget and page title")
    ccWidgetSecondaryText: {
        if (vpnActivating)
            return I18n.tr("Connecting...");
        if (!vpnActivated)
            return I18n.tr("Disconnected");
        const names = CyNetworkService.activeNames || [];
        if (names.length <= 1)
            return names[0] || I18n.tr("Connected");
        return names[0] + " +" + (names.length - 1);
    }
    ccWidgetIsActive: vpnActivated

    onCcWidgetToggled: CyNetworkService.toggleVpn()

    ccDetailContent: Component {
        VpnDetailContent {}
    }
    ccExpandedContent: Component {
        CcTileActions {
            actions: CyNetworkService.profiles.map(profile => ({
                        text: profile.name,
                        icon: "vpn_key",
                        toggle: true,
                        active: CyNetworkService.vpnStateForUuid(profile.uuid) === "activated",
                        enabled: !CyNetworkService.isVpnConnectingUuid(profile.uuid),
                        trigger: () => CyNetworkService.toggle(profile.uuid)
                    }))
        }
    }
}
