pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

Singleton {
    id: root

    readonly property bool wantsLocation: SettingsData.weatherEnabled && SettingsData.useAutoLocation
    readonly property bool locationAvailable: CyShellService.isConnected && CyShellService.capabilities.includes("location")
    readonly property bool valid: latitude !== 0 || longitude !== 0

    property var latitude: 0.0
    property var longitude: 0.0

    signal locationChanged(var data)

    onWantsLocationChanged: {
        if (wantsLocation) {
            ensureSubscription();
        } else if (CyShellService.activeSubscriptions.includes("location")) {
            CyShellService.removeSubscription("location");
        }
    }

    onLocationAvailableChanged: ensureSubscription()

    Component.onCompleted: ensureSubscription()

    Connections {
        target: CyShellService

        function onConnectionStateChanged() {
            if (CyShellService.isConnected)
                root.ensureSubscription();
        }

        function onLocationStateUpdate(data) {
            if (!root.wantsLocation)
                return;
            root.handleStateUpdate(data);
        }
    }

    function ensureSubscription() {
        if (!wantsLocation)
            return;
        if (!locationAvailable)
            return;
        if (CyShellService.activeSubscriptions.includes("location"))
            return;
        if (CyShellService.activeSubscriptions.includes("all"))
            return;

        CyShellService.addSubscription("location");
        if (!valid)
            getState();
    }

    function handleStateUpdate(data) {
        const lat = data.latitude;
        const lon = data.longitude;
        if (lat === 0 && lon === 0)
            return;

        root.latitude = lat;
        root.longitude = lon;
        root.locationChanged(data);
    }

    function getState() {
        if (!wantsLocation)
            return;
        if (!locationAvailable)
            return;

        CyShellService.sendRequest("location.getState", null, response => {
            if (response.result)
                handleStateUpdate(response.result);
        });
    }
}
