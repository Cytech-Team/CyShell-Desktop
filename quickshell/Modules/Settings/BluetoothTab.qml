pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.Modules.ControlCenter.Details
import qs.Services

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var pendingCodecDevice: null
    readonly property var adapter: BluetoothService.adapter
    readonly property bool adapterEnabled: adapter?.enabled ?? false
    readonly property int pairedDeviceCount: BluetoothService.pairedDevices.length
    readonly property int connectedDeviceCount: {
        const devices = BluetoothService.devices?.values ?? [];
        return devices.filter(device => device?.connected).length;
    }

    function showCodecSelector(device) {
        pendingCodecDevice = device;
        codecSelectorLoader.active = true;
        if (codecSelectorLoader.item) {
            codecSelectorLoader.item.show(device);
            pendingCodecDevice = null;
        }
    }

    Column {
        anchors.fill: parent
        spacing: 0

        Item {
            id: actionsHost
            width: parent.width
            height: CcMetrics.pageHeaderHeight

            Component.onCompleted: {
                const actions = bluetoothDetail.headerActions;
                if (!actions)
                    return;
                actions.parent = actionsHost;
            }
        }

        CcGroup {
            id: adapterControl
            width: parent.width

            CcToggleRow {
                iconName: "bluetooth"
                text: I18n.tr("Bluetooth")
                description: root.adapter ? I18n.tr("%1 · %2 paired · %3 connected", "Bluetooth adapter and device counts").arg(root.adapter.name || root.adapter.adapterId).arg(root.pairedDeviceCount).arg(root.connectedDeviceCount) : I18n.tr("No Bluetooth adapter found")
                checked: root.adapterEnabled
                enabled: !!root.adapter
                onToggled: BluetoothService.toggleBluetooth()
            }
        }

        BluetoothDetail {
            id: bluetoothDetail
            width: parent.width
            height: Math.max(0, parent.height - actionsHost.height - adapterControl.height)
            showAdapterToggle: false
            onShowCodecSelector: device => root.showCodecSelector(device)
        }
    }

    Binding {
        target: bluetoothDetail.headerActions
        property: "width"
        value: bluetoothDetail.headerActions.implicitWidth
    }

    Binding {
        target: bluetoothDetail.headerActions
        property: "height"
        value: actionsHost.height
    }

    Binding {
        target: bluetoothDetail.headerActions
        property: "x"
        value: I18n.isRtl ? 0 : actionsHost.width - bluetoothDetail.headerActions.implicitWidth
    }

    Loader {
        id: codecSelectorLoader
        anchors.fill: parent
        z: 10
        active: false
        sourceComponent: BluetoothCodecSelector {
            anchors.fill: parent
            onDismissed: Qt.callLater(() => codecSelectorLoader.active = false)
        }
        onLoaded: {
            if (root.pendingCodecDevice) {
                item.show(root.pendingCodecDevice);
                root.pendingCodecDevice = null;
            }
        }
    }
}
