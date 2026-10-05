import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.CyCommon.Common as DC

ShellRoot {
    id: root

    Component.onCompleted: {
        Quickshell.watchFiles = false;
        DC.Style.theme = Theme;
        DC.Style.settings = SettingsData;
        DC.I18n.backend = I18n;
        const paths = ["Modals/CyLauncherV2/CyLauncherV2ModalHost.qml", "Modules/CyIsland/Activities/LauncherExpanded.qml"];
        let failed = false;
        for (const path of paths) {
            const component = Qt.createComponent(path);
            if (component.status !== Component.Ready) {
                failed = true;
                console.log("FIXTURE_FAIL " + path + ": " + component.errorString());
            }
        }
        console.log(failed ? "FIXTURE_FAIL see above" : "FIXTURE_PASS " + paths.length + " launcher components compile");
        quitTimer.start();
    }

    Timer {
        id: quitTimer
        interval: 900
        onTriggered: Qt.quit()
    }
}
